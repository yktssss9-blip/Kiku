import { setGlobalOptions } from "firebase-functions";
import { onDocumentCreated, onDocumentUpdated } from "firebase-functions/v2/firestore";
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
const APP_BUNDLE_ID = "com.yukichi.kiku";
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

function sendRegularApnsPush(
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
      "apns-topic": APP_BUNDLE_ID,
      "apns-push-type": "alert",
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
        reject(new Error(`APNs alert push failed status=${status} body=${responseBody}`));
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

export const sendReminderRequest = onDocumentCreated(
  {
    document: "reminderRequests/{requestId}",
    secrets: [apnsAuthKey, apnsKeyId, apnsTeamId],
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const { questionId, requestedBy } = snapshot.data() as {
      questionId: string;
      requestedBy: string;
    };

    await snapshot.ref.delete();

    if (!questionId || !requestedBy) return;

    const questionDoc = await admin.firestore().collection("questions").doc(questionId).get();
    if (!questionDoc.exists) return;

    const question = questionDoc.data()!;
    if (question.createdBy !== requestedBy) return;

    const answers: Record<string, { value: string }> = question.answers ?? {};
    const pendingMemberIds = Object.entries(answers)
      .filter(([, v]) => v.value === "pending")
      .map(([memberId]) => memberId);

    if (pendingMemberIds.length === 0) return;

    const recipientMemberMap: Record<string, string> = question.recipientMemberMap ?? {};
    const memberToUid: Record<string, string> = {};
    for (const [uid, memberId] of Object.entries(recipientMemberMap)) {
      memberToUid[memberId as string] = uid;
    }

    const targetUIDs = [...new Set(pendingMemberIds.map((mid) => memberToUid[mid]).filter(Boolean))];
    if (targetUIDs.length === 0) return;

    const userDocs = await admin
      .firestore()
      .getAll(...targetUIDs.map((uid) => admin.firestore().collection("users").doc(uid)));

    const fcmFallbackMessages: admin.messaging.Message[] = [];
    let apnsSuccessCount = 0;

    for (const doc of userDocs) {
      const apnsToken = doc.get("apnsDeviceToken") as string | undefined;
      const fcmToken = doc.get("fcmToken") as string | undefined;
      const memberId = recipientMemberMap[doc.id];

      if (apnsToken && memberId) {
        const payload = {
          aps: {
            alert: {
              title: "⏰ まだ回答がありません",
              body: question.text as string,
            },
            sound: "default",
          },
          questionId,
          memberId,
          isReminder: "true",
        };
        try {
          await sendRegularApnsPush(apnsToken, payload);
          apnsSuccessCount++;
        } catch (error) {
          logger.error(`リマインドAPNs送信失敗 uid=${doc.id}`, error);
          if (fcmToken) {
            fcmFallbackMessages.push({
              token: fcmToken,
              notification: { title: "⏰ まだ回答がありません", body: question.text as string },
              data: { questionId, memberId: memberId ?? "", isReminder: "true" },
            });
          }
        }
      } else if (fcmToken) {
        fcmFallbackMessages.push({
          token: fcmToken,
          notification: { title: "⏰ まだ回答がありません", body: question.text as string },
          data: { questionId, memberId: memberId ?? "", isReminder: "true" },
        });
      }
    }

    if (fcmFallbackMessages.length > 0) {
      const response = await admin.messaging().sendEach(fcmFallbackMessages);
      logger.info(
        `リマインド送信: questionId=${questionId} APNs=${apnsSuccessCount} FCM成功=${response.successCount} FCM失敗=${response.failureCount}`
      );
    } else {
      logger.info(`リマインド送信: questionId=${questionId} APNs=${apnsSuccessCount}`);
    }
  }
);

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

    // 送信者のプロフィールを取得して通知タイトルを構築
    let notificationTitle = "きく";
    if (createdBy) {
      const creatorDoc = await admin.firestore().collection("users").doc(createdBy).get();
      const creatorName = (creatorDoc.get("name") as string) ?? "";
      const creatorEmoji = (creatorDoc.get("emoji") as string) ?? "";
      if (creatorName) {
        notificationTitle = creatorEmoji
          ? `${creatorEmoji} ${creatorName}さんから質問が届きました`
          : `${creatorName}さんから質問が届きました`;
      }
    }

    const choices: string[] = Array.isArray(question.choices) ? question.choices : ["yes", "no"];
    const categoryId = "KIKU_" + choices.map(String).sort().join("_");

    const fcmFallbackMessages: admin.messaging.Message[] = [];
    const pushToStartTargets: { deviceToken: string; uid: string }[] = [];
    let apnsSuccessCount = 0;

    for (const doc of userDocs) {
      const apnsToken = doc.get("apnsDeviceToken") as string | undefined;
      const fcmToken = doc.get("fcmToken") as string | undefined;
      const memberId = recipientMemberMap[doc.id];

      if (apnsToken && memberId) {
        const payload = {
          aps: {
            alert: {
              title: notificationTitle,
              body: text,
            },
            sound: "default",
            category: categoryId,
            "mutable-content": 1,
          },
          questionId,
          memberId,
        };
        try {
          await sendRegularApnsPush(apnsToken, payload);
          apnsSuccessCount++;
        } catch (error) {
          logger.error(`通知APNs送信失敗 uid=${doc.id}`, error);
          if (fcmToken) {
            const data: Record<string, string> = { questionId };
            if (memberId) data.memberId = memberId;
            fcmFallbackMessages.push({
              token: fcmToken,
              notification: { title: notificationTitle, body: text },
              data,
              apns: { payload: { aps: { sound: "default", category: categoryId } } },
            });
          }
        }
      } else if (fcmToken) {
        const data: Record<string, string> = { questionId };
        if (memberId) data.memberId = memberId;
        fcmFallbackMessages.push({
          token: fcmToken,
          notification: { title: notificationTitle, body: text },
          data,
          apns: { payload: { aps: { sound: "default", category: categoryId } } },
        });
      }

      const pushToStartToken = doc.get("liveActivityPushToStartToken") as string | undefined;
      if (pushToStartToken && memberId) {
        pushToStartTargets.push({ deviceToken: pushToStartToken, uid: doc.id });
      }
    }

    if (fcmFallbackMessages.length > 0) {
      const response = await admin.messaging().sendEach(fcmFallbackMessages);
      logger.info(
        `通知送信: questionId=${questionId} APNs=${apnsSuccessCount} FCM成功=${response.successCount} FCM失敗=${response.failureCount}`
      );
    } else {
      logger.info(`通知送信: questionId=${questionId} APNs=${apnsSuccessCount}`);
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

// MARK: - 友達申請通知

export const notifyOnFriendRequest = onDocumentCreated(
  {
    document: "friendRequests/{requestId}",
    secrets: [apnsAuthKey, apnsKeyId, apnsTeamId],
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const data = snapshot.data();
    const toUID: string = data.toUID ?? "";
    const fromName: string = data.fromName ?? "きく";
    const fromEmoji: string = data.fromEmoji ?? "👤";
    const fromUsername: string = data.fromUsername ?? "";
    const requestId = event.params.requestId;

    if (!toUID) return;

    const userDoc = await admin.firestore().collection("users").doc(toUID).get();
    const apnsToken = userDoc.get("apnsDeviceToken") as string | undefined;
    const fcmToken = userDoc.get("fcmToken") as string | undefined;

    if (!apnsToken && !fcmToken) {
      logger.info(`notifyOnFriendRequest: トークン未登録 uid=${toUID}`);
      return;
    }

    const notificationTitle = `${fromEmoji} ${fromName}さんから友達申請が届きました`;
    const notificationBody = `@${fromUsername}`;
    const extraData = {
      type: "friendRequest",
      requestId,
      fromUID: data.fromUID ?? "",
      fromName,
      fromEmoji,
      fromPhotoURL: data.fromPhotoURL ?? "",
    };

    if (apnsToken) {
      const payload = {
        aps: {
          alert: {
            title: notificationTitle,
            body: notificationBody,
          },
          sound: "default",
          category: "FRIEND_REQUEST",
        },
        ...extraData,
      };
      try {
        await sendRegularApnsPush(apnsToken, payload);
        logger.info(`友達申請通知送信(APNs): requestId=${requestId} to=${toUID}`);
        return;
      } catch (error) {
        logger.error(`友達申請APNs送信失敗 uid=${toUID}`, error);
      }
    }

    if (fcmToken) {
      await admin.messaging().send({
        token: fcmToken,
        notification: { title: notificationTitle, body: notificationBody },
        data: extraData,
        apns: { payload: { aps: { category: "FRIEND_REQUEST", sound: "default" } } },
      });
      logger.info(`友達申請通知送信(FCM): requestId=${requestId} to=${toUID}`);
    }
  }
);

// MARK: - 友達申請承認通知

export const notifyOnFriendRequestAccepted = onDocumentUpdated(
  {
    document: "friendRequests/{requestId}",
    secrets: [apnsAuthKey, apnsKeyId, apnsTeamId],
  },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;

    // pending → accepted の変化のみ処理
    if (before.status === "accepted" || after.status !== "accepted") return;

    const fromUID: string = after.fromUID ?? "";
    const toName: string = after.toName ?? "きく";
    const toEmoji: string = after.toEmoji ?? "👤";
    const toUsername: string = after.toUsername ?? "";
    const requestId = event.params.requestId;

    if (!fromUID) return;

    const userDoc = await admin.firestore().collection("users").doc(fromUID).get();
    const apnsToken = userDoc.get("apnsDeviceToken") as string | undefined;
    const fcmToken = userDoc.get("fcmToken") as string | undefined;

    if (!apnsToken && !fcmToken) {
      logger.info(`notifyOnFriendRequestAccepted: トークン未登録 uid=${fromUID}`);
      return;
    }

    const notificationTitle = `${toEmoji} ${toName}さんが友達申請を承認しました`;
    const notificationBody = `@${toUsername}`;
    const extraData = {
      type: "friendRequestAccepted",
      requestId,
      toUID: after.toUID ?? "",
      toName,
      toEmoji,
      toPhotoURL: after.toPhotoURL ?? "",
    };

    if (apnsToken) {
      const payload = {
        aps: {
          alert: { title: notificationTitle, body: notificationBody },
          sound: "default",
        },
        ...extraData,
      };
      try {
        await sendRegularApnsPush(apnsToken, payload);
        logger.info(`友達申請承認通知送信(APNs): requestId=${requestId} to=${fromUID}`);
        return;
      } catch (error) {
        logger.error(`友達申請承認APNs送信失敗 uid=${fromUID}`, error);
      }
    }

    if (fcmToken) {
      await admin.messaging().send({
        token: fcmToken,
        notification: { title: notificationTitle, body: notificationBody },
        data: extraData,
      });
      logger.info(`友達申請承認通知送信(FCM): requestId=${requestId} to=${fromUID}`);
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

// MARK: - チャットメッセージ通知

export const notifyOnChatMessage = onDocumentUpdated(
  {
    document: "chats/{questionId}",
    secrets: [apnsAuthKey, apnsKeyId, apnsTeamId],
  },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;

    const beforeMessages = (before.messages as Record<string, unknown>[]) ?? [];
    const afterMessages = (after.messages as Record<string, unknown>[]) ?? [];

    // 追加された新着メッセージを ID で検出
    const beforeIds = new Set(beforeMessages.map((m) => m.id as string));
    const newMessages = afterMessages.filter((m) => !beforeIds.has(m.id as string));

    // senderFirebaseUID があるメッセージ（ユーザーが送信したもの）だけ通知
    const userMessages = newMessages.filter(
      (m) => typeof m.senderFirebaseUID === "string" && m.senderFirebaseUID
    );
    if (userMessages.length === 0) return;

    const latest = userMessages[userMessages.length - 1];
    const senderFirebaseUID = latest.senderFirebaseUID as string;
    const senderName = (latest.senderName as string) ?? "";
    const senderEmoji = (latest.senderEmoji as string) ?? "";
    const text = (latest.text as string) ?? "";
    const questionId = (after.questionId as string) ?? event.params.questionId;

    const participantUIDs = (after.participantUIDs as string[]) ?? [];
    const recipients = participantUIDs.filter((uid) => uid !== senderFirebaseUID);
    if (recipients.length === 0) return;

    const notifTitle = senderEmoji ? `${senderEmoji} ${senderName}` : senderName;
    const extraData = { type: "chatMessage", questionId };

    for (const uid of recipients) {
      const userDoc = await admin.firestore().collection("users").doc(uid).get();
      const apnsToken = userDoc.get("apnsDeviceToken") as string | undefined;
      const fcmToken = userDoc.get("fcmToken") as string | undefined;

      if (!apnsToken && !fcmToken) {
        logger.info(`notifyOnChatMessage: トークン未登録 uid=${uid}`);
        continue;
      }

      if (apnsToken) {
        const payload = {
          aps: {
            alert: { title: notifTitle, body: text },
            sound: "default",
            category: "CHAT_MESSAGE",
          },
          ...extraData,
        };
        try {
          await sendRegularApnsPush(apnsToken, payload);
          logger.info(`チャット通知送信(APNs): questionId=${questionId} to=${uid}`);
          continue;
        } catch (error) {
          logger.error(`チャット通知APNs送信失敗 uid=${uid}`, error);
        }
      }

      if (fcmToken) {
        await admin.messaging().send({
          token: fcmToken,
          notification: { title: notifTitle, body: text },
          data: extraData,
          apns: { payload: { aps: { category: "CHAT_MESSAGE", sound: "default" } } },
        });
        logger.info(`チャット通知送信(FCM): questionId=${questionId} to=${uid}`);
      }
    }
  }
);
