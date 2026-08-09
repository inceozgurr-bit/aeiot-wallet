# AEIOT Wallet

A self-custody iOS wallet for Bitcoin, Ethereum, Solana, XRP and four EVM L2s —
built with SwiftUI, with no backend of its own.

Your recovery phrase is generated on the device and stored only in its Keychain.
There is no server, no account and no analytics.

## Networks

| Network | Balance | Receive | Send | Swap |
|---|:--:|:--:|:--:|:--:|
| Bitcoin (native SegWit) | ✅ | ✅ | ✅ | — |
| Ethereum | ✅ | ✅ | ✅ | ✅ |
| Base | ✅ | ✅ | ✅ | ✅ |
| Polygon | ✅ | ✅ | ✅ | ✅ |
| BNB Chain | ✅ | ✅ | ✅ | ✅ |
| Arbitrum, Optimism | ✅ | ✅ | ✅ | — ¹ |
| Solana (SOL + SPL) | ✅ | ✅ | ✅ | — |
| XRP Ledger | ✅ | ✅ | ✅ | — |

¹ Swapping is disabled where the available V2 pools quote far below spot price.

## No third-party crypto libraries

Solana/XRP/Bitcoin libraries pull in their own `secp256k1`, which collides with
the one `web3swift` already uses. The primitives are implemented here instead
and checked against the official test vectors:

| Component | Verified against |
|---|---|
| `SolanaKey` (ed25519, SLIP-0010) | SLIP-0010 vectors, independent implementation, live network |
| `XRPKey` / `XRPTransaction` | independent implementation, live network accepted the serialization |
| `BitcoinKey` / `BitcoinTransaction` | BIP84 spec vectors, BIP143 signing |
| `Bech32` | BIP173 vectors, corrupted-address rejection |
| `Ripemd160` | RFC test vectors |

## Security

- Recovery phrase in the Keychain, biometry-gated, never leaves the device
- Face ID required to send funds and to reveal the phrase, regardless of settings
- Recovery phrase hidden while the screen is being recorded
- Copied addresses and phrases expire from the pasteboard after 60 seconds
- Jailbreak warning at launch

## Build

```sh
cd ios && xcodegen generate
xcodebuild -project AEIOTWallet.xcodeproj -scheme AEIOTWallet \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Contracts: `cd contracts && forge test`

## Status

The signing paths are verified against specifications and live network
responses, but have not yet been exercised with real funds on every chain.
Test with small amounts first.

## License

MIT
