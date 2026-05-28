# Module 11: Notifications & Activity Feed — Security Audit

## Status

**Not started.** No backend or frontend code exists for this module.

---

## Planned Scope

**Expected backend files (not yet created):**
- `SimPle.Api/Controllers/NotificationsController.cs`
- `SimPle.Application/Notifications/Services/NotificationService.cs`
- `SimPle.Domain/Notifications/Notification.cs`

---

## Planned Features

- In-app notifications (friend requests, match invites, achievements)
- Activity feed (recent actions by friends)
- Mark as read / dismiss
- Optional email notification preferences

---

## Security Requirements For Implementation

| Requirement | Why |
|---|---|
| Authenticate all notification reads | Notifications are per-user and private |
| IDOR on mark-as-read | Users may only mark their own notifications as read; check ownership before update |
| Pagination | Activity feeds can be large; unbounded queries cause database load |
| No PII of third parties in notifications | Notification payloads should not expose email addresses or sensitive data of other users |
| Rate-limit notification dispatch | Avoid sending thousands of notifications from a single action (fan-out attack) |
| Email unsubscribe link must be one-click and authenticated | Unsubscribe links must use a signed token, not an unauthenticated user ID |
| No sensitive content in push notification payloads | Push payloads sent via FCM/APNs are visible to the notification infrastructure |

---

## Findings

None — module not yet implemented.

---

## Remaining Risks

| Risk | Notes |
|---|---|
| IDOR on notifications | Must verify user ownership before every read or dismiss operation |
| Unsubscribe link security | Unsigned unsubscribe links let anyone unsubscribe a victim from all emails |

---

## Audit Status

Planned. Will be reviewed when implementation begins.
