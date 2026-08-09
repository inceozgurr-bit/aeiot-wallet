# App Store Connect — listing copy

Paste-ready text for the App Store Connect form. Nothing here is compiled into
the app; it exists so the wording is reviewed and version-controlled rather than
improvised into the web form.

App: AEIOT · Bundle ID `aeiot.app001` · Apple ID 6799625313 · Team JMLSCK7G9U

---

## Subtitle (max 30 characters)

`Self-custody crypto wallet` — 26 characters.

Alternatives, all within the limit:
- `Your keys, your coins` (21)
- `Multi-chain crypto wallet` (25)

## Promotional text (max 170 characters, editable without a new build)

Your keys and your recovery phrase never leave your iPhone. Nine networks, one
app, no accounts and no tracking.

## Description

AEIOT Wallet is a self-custody wallet: your 12-word recovery phrase is created
on your iPhone, stored in its Keychain behind Face ID, and never sent anywhere.
There is no account to sign up for and no server holding your coins — only you
can move them.

WHAT IT DOES
• Hold, send and receive across nine networks: Base, Ethereum, Arbitrum,
  Optimism, Polygon, BNB Chain, Solana, the XRP Ledger and Bitcoin
• One address across the six EVM networks; Solana, XRP and Bitcoin get their own
• See balances and transaction history in one list, grouped by coin
• Swap tokens within a network through Uniswap pools, with the price and the
  network fee shown before you confirm
• Connect to web3 apps over WalletConnect — every signature is shown in full and
  needs Face ID
• Address book, QR scanning, and a printable recovery sheet

BUILT TO BE BORING ABOUT SECURITY
• The recovery phrase is readable only with Face ID or Touch ID, never with the
  device passcode alone
• Sending coins and revealing the phrase always ask for biometrics, even when
  the app-open lock is switched off
• The backup screen hides itself from screen recordings and warns on screenshots
• No analytics, no advertising, no tracking — the app has no server of its own

18 LANGUAGES
English, Turkish, Spanish, German, French, Italian, Portuguese, Dutch, Russian,
Ukrainian, Arabic, Hindi, Indonesian, Thai, Vietnamese, Simplified Chinese,
Japanese and Korean, with right-to-left layout for Arabic.

ABOUT AEIOT
AEIOT is a fixed-supply ERC-20 token on the Base network, total supply
1,150,115, with no way to create more. It carries no promise of value or return,
and nothing in this app is investment advice.

IMPORTANT
Self-custody has no undo. If you lose your 12 words, nobody — including the
developer — can restore your wallet. Blockchain transfers cannot be cancelled or
reversed, including transfers sent to a wrong address.

## Keywords (max 100 characters, comma-separated, no spaces)

`wallet,crypto,bitcoin,ethereum,solana,xrp,web3,defi,selfcustody,seedphrase,base,token`

That string is 84 characters. Do not repeat words already in the app name or
subtitle — Apple indexes those separately.

## URLs

- Support URL: `https://<user>.github.io/AEIOT/` (docs/index.html)
- Privacy Policy URL: `https://<user>.github.io/AEIOT/privacy.html` (docs/privacy.html)
- Marketing URL: optional, leave blank

To publish both: push the repo to GitHub, then Settings → Pages → Source:
`main` branch, `/docs` folder. Replace `<user>` above with the GitHub account.

## Age rating

17+ is the usual outcome for a crypto wallet. Answer the questionnaire honestly;
the app has no objectionable content, "Unrestricted Web Access" is **No** (there
is no in-app browser), and there is no gambling or contests.

## App Review notes

Suggested text for the reviewer, addressing the two things that get crypto
wallets rejected:

> AEIOT Wallet is a self-custody wallet. It does not custody funds, does not
> operate an exchange, and has no accounts or server. Keys are generated and
> stored on the device only.
>
> The swap feature calls the public Uniswap V2 router contract directly from the
> user's own wallet on the same network — it is an on-chain transaction the user
> signs, not a service we operate, and not a fiat on/off ramp.
>
> AEIOT is a fixed-supply ERC-20 token (1,150,115, no minting) included as one of
> the listed tokens. It is not offered for sale by the developer, is not marketed
> as an investment, and the app states in-app that it carries no promise of value
> or return.
>
> To test: tap Create New Wallet, write down the 12 words, confirm them, and the
> wallet opens with zero balances. No account or test credentials are needed.
> Face ID must be enrolled to reveal the recovery phrase
> (Simulator → Features → Face ID → Enrolled).

## Still needed before submitting

- [ ] Screenshots: 6.9" iPhone (1320×2868) required; 6.5" recommended
- [ ] Confirm the Apple Developer account is enrolled as an **Organization**,
      not an Individual — guideline 3.1.5(b) requires it for wallet apps, and
      this is the most common rejection reason for wallets
- [ ] Publish docs/ via GitHub Pages and paste the two URLs above
