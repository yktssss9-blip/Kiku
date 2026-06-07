import { setGlobalOptions } from "firebase-functions";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { defineSecret } from "firebase-functions/params";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import * as http2 from "http2";
import * as jwt from "jsonwebtoken";
import { randomUUID } from "crypto";

admin.initializeApp();

setGlobalOptions({ maxInstances: 10 });

const apnsAuthKey = defineSecret("APNS_AUTH_KEY");
const apnsKeyId = defineSecret("APNS_KEY_ID");
const apnsTeamId = defineSecret("APNS_TEAM_ID");

const APNS_HOST = "api.push.apple.com";
const LIVE_ACTIVITY_PUSH_TYPE_TOPIC = "com.yukichi.kiku.push-type.liveactivity";
const PROVIDER_TOKEN_TTL_SECONDS = 50 * 60;

let cachedProviderToken: { token: string; issuedAt: number } | null = null;

function getApnsProviderToken(): string {
  const now = Math.floor(Date.now() / 1000);
  if (cachedProviderToken && now - cachedProviderToken.issuedAt < PROVIDER_TOKEN_TTL_SECONDS) {
    return cachedProviderToken.token;
  }

  const token = jwt.sign({}, apnsAuthKey.value().replace(/\\n/g, "\n"), {
    algorithm: "ES256",
    issuer: apnsTeamId.value(),
    keyid: apnsKeyId.value(),
  });

  cachedProviderToken = { token, issuedAt: now };
  return token;
}

function sendLiveActivityPushToStart(
  deviceToken: string,
  payload: Record<string, unknown>
): Promise<void> {
  return new Promise((resolve, reject) => {
    const client = http2.connect(`https://${APNS_HOST}`);
    client.on("error", reject);

    const body = JSON.stringify(payload);
    const req = client.request({
      [http2.constants.HTTP2_HEADER_METHOD]: "POST",
      [http2.constants.HTTP2_HEADER_PATH]: `/3/device/${deviceToken}`,
      authorization: `bearer ${getApnsProviderToken()}`,
      "apns-topic": LIVE_ACTIVITY_PUSH_TYPE_TOPIC,
      "apns-push-type": "liveactivity",
      "apns-priority": "10",
      "content-length": Buffer.byteLength(body),
    });

    let status = 0;
    let responseBody = "";

    req.on("response", (headers) => {
      status = Number(headers[http2.constants.HTTP2_HEADER_STATUS]);
    });
    req.setEncoding("utf8");
    req.on("data", (chunk) => {
      responseBody += chunk;
    });
    req.on("end", () => {
      client.close();
      if (status >= 200 && status < 300) {
        resolve();
      } else {
        reject(new Error(`APNs push-to-start failed status=${status} body=${responseBody}`));
      }
    });
    req.on("error", (err) => {
      client.close();
      reject(err);
    });

    req.write(body);
    req.end();
  });
}

export const notifyOnQuestionCreated = onDocumentCreated(
  {
    document: "questions/{questionId}",
    secrets: [apnsAuthKey, apnsKeyId, apnsTeamId],
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      return;
    }

    const question = snapshot.data();
    const questionId = event.params.questionId;
    const createdBy: string | undefined = question.createdBy;
    const recipientUIDs: string[] = Array.isArray(question.recipientUIDs)
      ? question.recipientUIDs
      : [];
    const recipientMemberMap: Record<string, string> =
      typeof question.recipientMemberMap === "object" && question.recipientMemberMap !== null
        ? question.recipientMemberMap
        : {};
    const memberNames: Record<string, string> =
      typeof question.memberNames === "object" && question.memberNames !== null
        ? question.memberNames
        : {};
    const text: string = question.text ?? "";
    const answers: Record<string, unknown> =
      typeof question.answers === "object" && question.answers !== null ? question.answers : {};
    const totalCount = Object.keys(answers).length;

    const targetUIDs = recipientUIDs.filter((uid) => uid !== createdBy);
    if (targetUIDs.length === 0) {
      return;
    }

    const userDocs = await admin.firestore().getAll(
      ...targetUIDs.map((uid) => admin.firestore().collection("users").doc(uid))
    );

    const messages: admin.messaging.Message[] = [];
    const pushToStartTargets: { deviceToken: string; uid: string }[] = [];
    for (const doc of userDocs) {
      const fcmToken = doc.get("fcmToken") as string | undefined;
      const memberId = recipientMemberMap[doc.id];
      if (fcmToken) {
        const data: Record<string, string> = { questionId };
        if (memberId) {
          data.memberId = memberId;
        }
        messages.push({
          token: fcmToken,
          notification: {
            title: "きく",
            body: text,
          },
          data,
        });
      }

      const pushToStartToken = doc.get("liveActivityPushToStartToken") as string | undefined;
      if (pushToStartToken && memberId) {
        pushToStartTargets.push({ deviceToken: pushToStartToken, uid: doc.id });
      }
    }

    if (messages.length > 0) {
      const response = await admin.messaging().sendEach(messages);
      logger.info(
        `通知送信: questionId=${questionId} 成功=${response.successCount} 失敗=${response.failureCount}`
      );
    }

    const sentAt = Math.floor(Date.now() / 1000);
    for (const target of pushToStartTargets) {
      const memberId = recipientMemberMap[target.uid];
      const memberName = memberNames[memberId] ?? "";
      const payload = {
        aps: {
          timestamp: sentAt,
          event: "start",
          "attributes-type": "KikuActivityAttributes",
          attributes: {
            questionId,
            questionText: text,
            totalCount,
            memberId,
            memberName,
            sentAt,
          },
          "content-state": {
            yesCount: 0,
            noCount: 0,
            pendingCount: totalCount,
          },
          alert: {
            title: "きく",
            body: text,
          },
        },
      };

      try {
        await sendLiveActivityPushToStart(target.deviceToken, payload);
        logger.info(`Live Activity push-to-start送信成功: questionId=${questionId} uid=${target.uid}`);
      } catch (error) {
        logger.error(
          `Live Activity push-to-start送信失敗: questionId=${questionId} uid=${target.uid}`,
          error
        );
      }
    }
  }
);

// MARK: - テンプレート自動送信

/**
 * ScheduleConfig（hour/minute/repeatType/weekdays）から次回送信日時を計算する。
 * weekdays は 1=日, 2=月, ..., 7=土（Swift側の ScheduleConfig と同じ規約）。
 */
function computeNextSendAt(schedule: Record<string, unknown>, from: Date): Date {
  const hour = typeof schedule.hour === "number" ? schedule.hour : 9;
  const minute = typeof schedule.minute === "number" ? schedule.minute : 0;
  const repeatType = schedule.repeatType === "weekly" ? "weekly" : "daily";

  if (repeatType === "daily") {
    const next = new Date(from);
    next.setHours(hour, minute, 0, 0);
    if (next <= from) {
      next.setDate(next.getDate() + 1);
    }
    return next;
  }

  const weekdays: number[] = Array.isArray(schedule.weekdays)
    ? schedule.weekdays.filter((d): d is number => typeof d === "number")
    : [];
  if (weekdays.length === 0) {
    const next = new Date(from);
    next.setHours(hour, minute, 0, 0);
    next.setDate(next.getDate() + 7);
    return next;
  }

  for (let offset = 0; offset <= 7; offset++) {
    const candidate = new Date(from);
    candidate.setDate(candidate.getDate() + offset);
    candidate.setHours(hour, minute, 0, 0);
    const configWeekday = candidate.getDay() + 1; // JS: 0=日 → config: 1=日
    if (weekdays.includes(configWeekday) && candidate > from) {
      return candidate;
    }
  }

  // 理論上到達しないフォールバック
  const fallback = new Date(from);
  fallback.setHours(hour, minute, 0, 0);
  fallback.setDate(fallback.getDate() + 7);
  return fallback;
}

export const sendScheduledTemplates = onSchedule(
  { schedule: "every 5 minutes", timeZone: "Asia/Tokyo" },
  async () => {
    const now = new Date();
    const dueTemplates = await admin
      .firestore()
      .collectionGroup("templates")
      .where("schedule.isEnabled", "==", true)
      .where("schedule.nextSendAt", "<=", admin.firestore.Timestamp.fromDate(now))
      .get();

    if (dueTemplates.empty) {
      return;
    }

    for (const doc of dueTemplates.docs) {
      const ownerUid = doc.ref.parent.parent?.id;
      if (!ownerUid) {
        continue;
      }

      const data = doc.data();
      const text: string = data.text ?? "";
      const choices: string[] = Array.isArray(data.choices) ? data.choices : ["yes", "no"];
      const friendIds: string[] = Array.isArray(data.friendIds) ? data.friendIds : [];
      if (friendIds.length === 0) {
        continue;
      }

      const memberNames =
        typeof data.memberNames === "object" && data.memberNames !== null ? data.memberNames : {};
      const recipientUIDs: string[] = Array.isArray(data.recipientUIDs) ? data.recipientUIDs : [];
      const recipientMemberMap =
        typeof data.recipientMemberMap === "object" && data.recipientMemberMap !== null
          ? data.recipientMemberMap
          : {};

      const answers: Record<string, unknown> = {};
      for (const memberId of friendIds) {
        answers[memberId] = { value: "pending", answeredAt: null };
      }

      const questionId = randomUUID();
      const questionData: Record<string, unknown> = {
        text,
        groupId: typeof data.groupId === "string" ? data.groupId : null,
        choices,
        createdAt: admin.firestore.Timestamp.fromDate(now),
        createdBy: ownerUid,
        inviteToken: randomUUID(),
        answers,
      };
      if (Object.keys(memberNames).length > 0) {
        questionData.memberNames = memberNames;
      }
      if (recipientUIDs.length > 0) {
        questionData.recipientUIDs = recipientUIDs;
      }
      if (Object.keys(recipientMemberMap).length > 0) {
        questionData.recipientMemberMap = recipientMemberMap;
      }

      await admin.firestore().collection("questions").doc(questionId).set(questionData);

      const schedule =
        typeof data.schedule === "object" && data.schedule !== null
          ? (data.schedule as Record<string, unknown>)
          : {};
      const nextSendAt = computeNextSendAt(schedule, now);
      await doc.ref.update({ "schedule.nextSendAt": admin.firestore.Timestamp.fromDate(nextSendAt) });

      logger.info(
        `テンプレート自動送信: templateId=${doc.id} owner=${ownerUid} questionId=${questionId} 次回=${nextSendAt.toISOString()}`
      );
    }
  }
);
