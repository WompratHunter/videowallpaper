# 11: Weather conditions in Daylight (WeatherKit)

**What to build:** Cloud cover and conditions (overcast, rain, storm) dim Daylight, so a stormy afternoon aims at darker videos and a clear one at brighter ones. Uses WeatherKit with the location already resolved for ticket 10. Fetch at most every 30–60 min while awake (exact interval and dimming curve decided when this is picked up); cache the last result with a short expiry; when offline, unauthorised or expired, Daylight falls back to sun position only. The pick logic does not change; weather only adjusts Daylight behind its existing interface.

**Blocked by:** 10; a paid Apple Developer Program membership (WeatherKit capability on the App ID, provisioning profile embedded in the `.app`)

**Status:** needs-info

- [ ] Waiting on: paid Developer Program membership
- [ ] Decide when picked up: refresh interval, how much each condition dims Daylight, whether a sudden storm may trigger an early switch
- [ ] Spec and README: the app now makes one network call (to Apple's WeatherKit); update the privacy wording
- [ ] Makefile embeds the provisioning profile and the WeatherKit entitlement when signing
- [ ] Pure tests for the condition → Daylight adjustment and the fallback when no weather is available
