# App Store Connect Metadata

## App Name
Octo Live

## Subtitle
Live home electricity usage

## Description
See your home electricity usage in real time, right from your home screen and lock screen.

Octo Live connects to your Octopus Energy account via their public API and displays live power demand from your Octopus Home Mini smart meter device. View your current usage, track consumption over time, and keep an eye on your daily total.

Features:
- Live electricity demand in the app, updated every 40 seconds
- Widgets refresh through the day as iOS allows, with a tap-to-refresh button
- Home screen widgets (small, medium, large)
- Lock screen widgets (circular, rectangular, inline)
- Interactive chart with adjustable time ranges (5m, 15m, 1h, 6h, 24h)
- Daily usage summary in kWh
- Dark theme designed for quick glancing

Requirements:
- An Octopus Energy account (octopus.energy)
- An Octopus Home Mini device connected to your smart meter
- Your API key (found on the Octopus website under Personal details → API access)

This app is not affiliated with, endorsed by, or connected to Octopus Energy Ltd.

## Keywords
<!-- No third-party trademarks (Guideline 2.3.7): "octopus" / "home mini" are left out on purpose. -->
energy,electricity,smart meter,widget,usage,power,live,monitor,kwh,watts,consumption,tracker

## Category
Primary: Utilities
Secondary: Lifestyle

## Support URL
https://citi94.github.io/OctopusLive/support

## Privacy Policy URL
https://citi94.github.io/OctopusLive/privacy

## App Review Notes
This app requires an Octopus Energy account with a Home Mini device to display live data. If you do not have an account, tap "Try with demo data" on the setup screen to preview the app's functionality with simulated readings.

The app uses the publicly documented Octopus Energy API (https://developer.octopus.energy/). Users authenticate with their own API key, which they generate from their Octopus Energy account. The API is free and publicly available. Multiple third-party apps using this API are already approved on the App Store (e.g. Octopus Watch, Octopus Mate).

No test account is needed - the demo mode demonstrates all features.

## App Store Privacy Labels

Select **Data Not Collected**.

Rationale: Apple defines "collect" as transmitting data off the device in a way
that lets the developer (or the developer's partners) access it. Octo Live
has no server, analytics or SDKs; the API key and account number stay on the
device and are sent only directly to the user's own energy supplier
(api.octopus.energy) to fetch their data. The developer never receives anything.
