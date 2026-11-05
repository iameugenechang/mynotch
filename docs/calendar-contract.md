# Calendar contract

`CalendarFeature` owns local-day queries and their publication lifetime. `CalendarManager` is the native preferences/presentation facade and receives `CalendarServiceProviding` from app composition. `CalendarService` owns EventKit and requests permission only through explicit authorization methods.

A query uses a half-open local-day interval, including daylight-saving changes. An empty selection means no calendars. Reminder deadlines at the next midnight belong to the next day. Native filtering cannot pass an empty calendar list into EventKit's implicit all-calendars query.

Loads distinguish success with no events, denied access, and failures. A nil reminder response is unavailable, not successful emptiness. Reminder mutations propagate errors to the facade instead of logging and reporting success. Replacement, cancellation, and terminal stop reject late results. Calendar-list reloads also have revision checks.

Four package cases test day boundaries, DST, empty selection, failure status, query replacement, cancellation, and terminal stop. The native conformance runner compiles production CalendarService with a controlled CalendarBackend. It verifies permission gating, per-entity selection, half-open filtering, empty selection without a query, and backend failures. The private EventKit backend remains the native effect layer; tests neither construct a real store nor request permission. Live EventKit mapping and OS permission acceptance remain manual.

Two behavior corrections are intentional: midnight reminders no longer appear on both days, and an empty/missing selected calendar no longer causes EventKit to return all calendars.
