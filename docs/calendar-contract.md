# Calendar contract

`CalendarFeature` owns local-day queries and their publication lifetime. `CalendarManager` is the native preferences/presentation facade and receives `CalendarServiceProviding` from app composition. `CalendarService` owns EventKit and requests permission only through explicit authorization methods.

A query uses a half-open local-day interval, including daylight-saving changes. An empty selection means no calendars. Reminder deadlines at the next midnight belong to the next day. Native filtering cannot pass an empty calendar list into EventKit's implicit all-calendars query.

Loads distinguish success with no events, denied access, and failures. A nil reminder response is unavailable, not successful emptiness. Reminder mutations propagate errors to the facade instead of logging and reporting success. Replacement, cancellation, and terminal stop reject late results. Calendar-list reloads also have revision checks.

Four package cases test day boundaries, DST, empty selection, failure status, query replacement, cancellation, and terminal stop. These do not access EventKit, request permission, or prove native adapter conformance. The unsigned app build verifies integration. Native store conformance and permission acceptance remain outstanding.

Two behavior corrections are intentional: midnight reminders no longer appear on both days, and an empty/missing selected calendar no longer causes EventKit to return all calendars.
