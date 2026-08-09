# AEIOT — Token + iOS Wallet

Özgür'ün kişisel coini **AEIOT** ve onu saklayan iOS cüzdanı. Özgür kod bilmiyor —
her rapor sade Türkçe, teknik jargon açıklanarak verilir.

## Yapı

| Klasör | İçerik |
|---|---|
| `contracts/` | Foundry projesi — `src/AEIOT.sol` (sabit arzlı ERC-20) + testler |
| `ios/` | xcodegen + SwiftUI cüzdan app'i (`AEIOTWallet`) |

## Zincir bilgileri (Base mainnet, chainID 8453)

- **AEIOT kontrat:** `0x173ed85989D27e5AE3B05A0dC95E6C9862303Fab` (deployer nonce-0'dan deterministik; deploy sonrası doğrula)
- **Deployer adres:** `0xE9B0dBf421B3BbCf532D77D6AA2896DbcaF2f94F`
- **Deployer private key:** macOS Keychain `security find-generic-password -s "AEIOT Deployer" -w` — ASLA dosyaya/koda yazma
- **Toplam arz:** 1.150.115 AEIOT (18 decimals), mint yok
- **RPC:** `https://mainnet.base.org`
- Cüzdanda gösterilen diğer tokenlar: ETH (native), USDC `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913`, USDT `0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2` (6 decimals), cbBTC `0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf`

## Komutlar

| İş | Komut |
|---|---|
| Kontrat test | `cd contracts && forge test` |
| Deploy (ETH yüklendikten sonra) | `cd contracts && forge create src/AEIOT.sol:AEIOT --rpc-url base --private-key $(security find-generic-password -s "AEIOT Deployer" -w) --broadcast --verify --verifier-url https://api.basescan.org/api` |
| iOS proje üret | `cd ios && xcodegen generate` |
| iOS build | `cd ios && xcodebuild -project AEIOTWallet.xcodeproj -scheme AEIOTWallet -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build` |

## iOS mimari notları

- **Bağımlılık:** yalnız `web3swift` (BIP39 + imzalama + ERC-20 ABI). EVM dışı zincirler (Solana/XRP/Bitcoin) için yeni bağımlılık gerekir — onay al.
- **Çoklu ağ:** `Chain.swift` → `ChainKind` = `.evm(chainID:)` | `.solana` | `.xrp`. Altı EVM ağı (Base, Ethereum, Arbitrum, Optimism, Polygon, BNB) aynı `0x…` adresi paylaşır; Solana ve XRP **ayrı adres** türetir (`WalletInfo.solanaAddress` / `.xrpAddress`, eski cüzdanlarda nil → `backfillAddresses()` bir kez Face ID ister). `ChainService.balance` ağ türüne göre `SolanaService`/`XRPService`/`BitcoinService`'e yönlenir.
- **Takas (ağ içi, köprü yok):** `Chain.swapRouter` + `wrappedNative` dolu olan ağlarda açık — Base, Ethereum, Polygon, BNB. **Arbitrum ve Optimism kasten kapalı:** SushiV2/UniV2 havuzları spot fiyatın %25–88 altında kote ediyor (1 WETH→USDC ölçüldü). Yeni ağ eklerken `getAmountsOut` ile spot fiyata karşı ölç, sadece kod varlığına bakma.
- **EVM dışı kripto, kütüphanesiz:** Solana kütüphaneleri `secp256k1.swift`'i çekip web3swift ile çakışıyor. Onun yerine kendi parçalarımız var:
  - `SolanaKey` — CryptoKit ed25519 + SLIP-0010, yol `m/44'/501'/0'/0'`
  - `XRPKey` + `XRPTransaction` — HDNode secp256k1, yol `m/44'/144'/0'/0/0`, `Ripemd160` + ripple base58; XRPL ikili kodlayıcıda alanlar **(tip, alan) artan sırada** yazılmalı
  - `BitcoinKey` + `BitcoinTransaction` — BIP84 `m/84'/0'/0'/0/0` (+ change `…/1/0`), `Bech32`, BIP143 SegWit imzalama. `txid` ağda **ters bayt sırasıyla** yazılır — atlanırsa işlem geçersiz olur.
  - `Ripemd160` — CryptoKit'te de CryptoSwift'te de yok, elde yazıldı
- **Doğrulama zorunlu:** adres/işlem üretimini değiştirirsen yeniden doğrula. Kullanılan kaynaklar: SLIP-0010 vektörü, BIP84 spec vektörleri, BIP173 bech32 vektörleri, RIPEMD160 RFC vektörleri, bağımsız Python hesabı, ve ağların kendisi (XRP `submit` → "Invalid signature" = format doğru; Solana/XRP adresleri ağda tanındı). Doğrulama paketi: `scratchpad/btcverify` (SPM, `swift run`).
- **Solana notu:** token hesabı adresi yerel olarak türetilmiyor, `getTokenAccountsByOwner` ile **ağa soruluyor** — yanlış türetme parayı kimsenin erişemediği adrese gönderir. Alıcının o token için hesabı yoksa gönderim net hatayla reddedilir.
- **Liste gruplaması:** aynı sembol tek satırda toplanır (`Token.grouped` → `TokenGroup`), rozet "N ağ" der, detayda ağ dağılımı listelenir. Bakiyeler `withTaskGroup` ile paralel çekilir — sıralı çekim 20 coinde saniyeler sürüyordu.
- **RPC kırılganlığı:** herkese açık RPC'ler kapanabiliyor (polygon-rpc.com API key istemeye başladı). Ağ eklerken/borç alırken `eth_chainId` ile test et. BNB Chain'in herkese açık Blockscout'u yok → o ağda işlem geçmişi gelmez.
- Kullanıcının seed phrase'i **iOS Keychain**'de (`WhenUnlockedThisDeviceOnly`), server yok.
- iOS 26 Liquid Glass (`.glassEffect`, `.buttonStyle(.glass)`).
- **Ayarlar** (`SettingsView`, toolbar sol üstteki dişli — eski "i" butonunun yeri): tema, dil, Face ID ile açma, AEIOT Hakkında, Kullanım Koşulları + Gizlilik Politikası (`LegalView`), sürüm.
- **Tema:** Açık/Koyu/Sistem (`ThemeMode`, `@AppStorage("themeMode")`, varsayılan **açık**). `preferredColorScheme` sheet'lere geçmediği için `UIWindow.overrideUserInterfaceStyle` kullanılıyor — tema kodu buradan değişir.
- **Tek vurgu rengi:** marka kırmızısı (`Color.appAccent`, logodan örneklendi; açık temada kontrast için biraz koyu), kökte `.tint`. Yeşil/turuncu/mavi yok; yön bilgisi ok ikonu + işaretle verilir, düşüş/giden `.secondary`.
- **Diller:** `Localizable.xcstrings` (kaynak `en` + `tr`) + izin metinleri için `en.lproj`/`tr.lproj/InfoPlist.strings`. Ayarlar'dan Türkçe/English seçilir (`AppLanguage`); ilk açılışta `deviceDefault` (cihaz Türkçe ise TR, diğer her dilde EN). `Localization` `Bundle.main`'i seçilen `.lproj`'a yönlendirir, kök view `.id(appLanguage)` ile yenilenir.
- **Lokalizasyon tuzakları:** `String(localized:)` bundle yönlendirmesini atlar — bunun yerine **`String.loc(...)`** kullan. Ternary içinde `Text(kosul ? "A" : "B")` yazma (çeviriye uğramaz), `LocalizedStringKey` değişkeni kullan.
- Face ID anahtarı yalnız **açılış kilidini** kapatır; para gönderme ve kurtarma cümlesi her koşulda biyometri ister.
- Fiyatlar CoinGecko free API; AEIOT'un fiyatı havuz açılana dek "No market yet".

## Faz durumu

- [x] Faz 1a: kontrat yazıldı, 6/6 test geçti
- [ ] Faz 1b: deployer'a ~$10 ETH (Base) — **Özgür'ün aksiyonu**
- [ ] Faz 1c: deploy + Basescan verify
- [x] Faz 2: cüzdan app — çoklu cüzdan + Face ID kilit (açılış+arka plan) + sistem teması + TR/EN otomatik (cihaz dili). Cüzdan listesi/seed'ler + adres defteri Keychain'de (app silinse kalıcı). Pencereler: Send/AddWallet tam ekran push (kenardan kayan), Receive/Import alttan sheet. Ekstra özellikler: bakiye gizle/göster, işlem geçmişi (Blockscout API, deploy sonrası dolar), adres defteri, AEIOT tanıtım kartı (toolbar sol üstteki info butonu → sheet), coin sparkles animasyonu. Hepsi simulator'da doğrulandı.
- [x] Faz 3: Uniswap v2 havuzu açıldı ($10 = 100k AEIOT + 0.0055 ETH). Swap sekmesi canlı — tüm çiftler (AEIOT/ETH/USDC/USDT/cbBTC) token-token dahil, WETH üzerinden çok-adımlı rota (`swapPath`: [A,WETH,B]). USDT (6 decimals) cüzdana + takasa eklendi, simulator'da 1000 AEIOT→0.167 USDT quote zincirle birebir doğrulandı.
