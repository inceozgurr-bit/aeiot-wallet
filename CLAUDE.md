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

## App Store Connect kaydı

| Alan | Değer |
|---|---|
| App adı | AEIOT (alt başlık boş, 30 karakter hakkı duruyor) |
| Bundle ID | `aeiot.app001` — App Store Connect'te kayıtlı, **sonradan değiştirilemez**; `project.yml` bununla birebir aynı olmalı yoksa yükleme reddedilir |
| SKU | `aeiot.app002` (yalnız Apple tarafında, kodda karşılığı yok) |
| Apple ID (app) | 6799625313 |
| Team ID | JMLSCK7G9U |
| Sürüm | `MARKETING_VERSION` 1.0 / `CURRENT_PROJECT_VERSION` 1 |

- **Bundle ID ≠ Keychain service:** `Keychain.service` bilerek `com.aeiot.wallet` kaldı. O string değişirse kayıtlı kurtarma cümleleri erişilemez olur — bundle ID'ye uydurmak için **dokunma**.
- Bundle ID `com.aeiot.wallet`'tan `aeiot.app001`'e geçtiği için, eski kimlikle kurulu cihazlardaki cüzdanlar Keychain erişim grubu değiştiğinden okunamaz; kurtarma cümlesiyle yeniden içe aktarılmaları gerekir.

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
- **Diller:** `Localizable.xcstrings` (kaynak `en`, 184 anahtar) + her dil için izin metinleri `<kod>.lproj/InfoPlist.strings`. `AppLanguage` **18 dil** tanımlar (en tr es de fr it pt nl ru uk ar hi id th vi zh-Hans ja ko) ama Ayarlar yalnız `AppLanguage.available` gösterir — bundle'da `.lproj`'u olan diller. **18 dilin hepsi hazır ve derleniyor** (her biri 184 anahtar; `tr` 6 sembol anahtarını İngilizce'den devralır). Ayarlar'daki liste **tr → en → uk** ile başlar (`available` içinde sabitlenmiş), kalanlar kendi adlarına göre sıralanır; popover 10 satır yüksekliğinde açılıp gerisini kaydırır. İlk açılışta `deviceDefault` cihaz diline en yakın *hazır* dili seçer; sonrası Ayarlar'daki seçim. `Localization` `Bundle.main`'i seçilen `.lproj`'a yönlendirir, kök view `.id(appLanguage)` ile yenilenir.
- **Dil eklerken:** (1) `Localizable.xcstrings`'e 184 anahtarın çevirisi, (2) `<kod>.lproj/InfoPlist.strings`, (3) `xcodegen generate` — `knownRegions`'a otomatik girer, (4) derlenen `.app` içinde `<kod>.lproj/Localizable.strings` var mı doğrula. `.lproj` yoksa dil sessizce İngilizce'ye düşer. Arapça geldiğinde RTL hazır: `AppLanguage.layoutDirection` → kökte `.environment(\.layoutDirection,…)`; iOS kendi çevirmez, çünkü uygulama içi dil seçimi cihaz dilini eziyor.
- **Uzun çeviri = bozulan düzen:** dar/sabit alandaki metne (buton, rozet, satır sonu değeri) **`.oneLine()`** ekle (`Theme.swift`; `lineLimit(1)` + `minimumScaleFactor`). Almanca "Empfangen" ana ekran butonlarını iki satıra kırıp buton yüksekliğini bozmuştu. Çok satırlı açıklama/legal metinlere **ekleme**.
- **Lokalizasyon tuzakları:** `String(localized:)` bundle yönlendirmesini atlar — bunun yerine **`String.loc(...)`** kullan. Ternary içinde `Text(kosul ? "A" : "B")` yazma (çeviriye uğramaz), `LocalizedStringKey` değişkeni kullan.
- Face ID anahtarı yalnız **açılış kilidini** kapatır; para gönderme ve kurtarma cümlesi her koşulda biyometri ister.
- Fiyatlar CoinGecko free API; AEIOT'un fiyatı havuz açılana dek "No market yet".

## WalletConnect

Cüzdanı dapp'lere bağlar. `WalletConnectService.swift` (SDK köprüsü + imzalama) ve `Views/WalletConnectViews.swift` (bağlantı isteği, imza isteği, bağlı uygulamalar).

- **Paket:** `reown-com/reown-swift`, ürün **`ReownWalletKit`** (WalletConnect'in yeni adı Reown), `exactVersion: 2.3.1` ile **sabitlenmiş** — ileride sessizce çakışan bir bağımlılık gelmesin diye; sürümü bilerek yükselt.
- **web3swift ile çakışmıyor** (gerçek build ile doğrulandı): reown `secp256k1.swift`/`CryptoSwift` çekmiyor. Solana kütüphanelerindeki sorun burada yok.
- **Yapılandırma:** Project ID `ios/Secrets.xcconfig` içinde (`REOWN_PROJECT_ID`, git'te değil — `.gitignore` `*.xcconfig`), `project.yml` bunu Info.plist'e `ReownProjectID` olarak geçirir. Yeni makinede bu dosyayı `cloud.reown.com` → proje "AEIOT" değerinden yeniden oluştur, yoksa eşleştirme çalışmaz.
- **App Group `group.aeiot.app001` zorunlu:** SDK kendi Keychain kayıtlarını bu erişim grubuna yazıyor ve eksikse yedek yolu yok. `project.yml`'daki `entitlements` bunu üretiyor; Apple tarafına `xcodebuild -allowProvisioningUpdates` ile otomatik kaydedildi (portal'da elle iş gerekmedi).
- **Kendi parçalarımız, yeni bağımlılık yok:** Reown röle soketi getirmiyor (örnek uygulaması Starscream kullanıyor) → `URLSessionWebSocketTask` ile yazıldı. `CryptoProvider` için keccak (CryptoSwift) + `SECP256K1.recoverPublicKey` (web3swift) yeterli. **Not:** `toHexString()` hem CryptoSwift hem web3swift'te var, doğrudan çağırmak "ambiguous" hatası verir.
- **Desteklenenler:** `personal_sign`, `eth_signTypedData(_v4)`. EIP-712 için elle kodlama gerekmedi — web3swift'te `EIP712Parser.parse` + `Web3Signer.signEIP712` hazır. **Kasten reddedilenler:** `eth_sign` (kullanıcıya bağlam göstermeden opak hash imzalar), `wallet_addEthereumChain` (dapp'ten RPC adresi kabul etmek). `eth_sendTransaction` **henüz yok** — sıradaki iş.
- **Güvenlik kuralı:** her imza `WalletStore.loadKeystore()` üzerinden **taze Face ID** ister; onaylı oturum imza yetkisi değildir. "Bu dapp için bir daha sorma" muafiyeti **asla** eklenmemeli.

## Güvenlik kararları (denetim sonrası — bozma)

- **Kurtarma cümlesi `.biometryCurrentSet` ile korunuyor** (`Keychain.swift`), `.userPresence` değil: cihaz parolası kabul edilmiyor. Bedeli bilinçli — Face ID yeniden kaydedilirse öğe geçersiz olur ve cüzdan 12 kelimeyle geri yüklenir. **Yalnız bu değişiklikten sonra yazılan cüzdanlar korunuyor**; eski kayıtlar eski ACL'de kalır.
- **Takas alt sınırı (`minOut`) asla metinden geçmez** (`ChainService.swap`): zincirin ham `BigUInt` cevabı × 85 / 100, üstelik imzalama anında yeniden sorulur. Eski `Decimal → String → parse` yolu ondalık taşmasında ve Arapça rakamlarda `nil` dönüp `?? 0` ile korumayı **tamamen kaldırıyordu**. `deadline` = şimdi + 20 dk (eskiden pratikte sonsuzdu). `approve` makbuzu beklenir.
- **Her imza taze Face ID ister** — `loadKeystore(reason:)`, istem metni işleme göre değişir. Desteklenmeyen yöntem keystore'a **dokunmadan** reddedilir. Oturum, dapp'in listesini değil `supportedMethods`'u ilan eder.
- **Keychain okumaları `Task.detached` içinde** (`WalletStore.secret`): main actor'da Face ID istemi arayüzü dondurur, 20+ sn'de iOS uygulamayı öldürür.
- **Dış kaynaklı metin doğrudan render edilmez** — token sembolleri ASCII alfanümerik + 12 karaktere kırpılır (`HistoryService.safeSymbol`); imza yükünde bidi/zero-width karakterler temizlenir (`WalletConnectService.sanitized`). SDK'nın `VerifyContext`'i (`.scam`/doğrulanamadı) onay ekranlarında gösterilir.
- **Kurtarma cümlesi diske yalnız istendiğinde iner**: PDF `ShareLink` yerine buton eylemiyle üretilir, `.completeFileProtection` ile yazılır, paylaşım kapanınca silinir. Pano kopyası `localOnly` (yoksa Handoff ile bağlı Mac'lere yayılır).
- **Bitcoin ücret oranı `maxFeeRate` (300 sat/vB) ile sınırlı**; gönderim onayında ücret satırı var.

## App Store dosyaları

`docs/` GitHub Pages ile yayınlanır (Settings → Pages → `main` / `/docs`): `privacy.html` (App Store Connect'in **zorunlu** politika adresi), `index.html` (destek adresi), `app-store-listing.md` (alt başlık, açıklama, anahtar kelimeler, App Review notu). `PrivacyInfo.xcprivacy` **olmadan yükleme reddedilir** (ITMS-91053) — `UserDefaults` için `CA92.1` beyanı içerir. Gizlilik metni uygulama içi `LegalView` ile birebir aynı kalmalı.

## Faz durumu

- [x] Faz 1a: kontrat yazıldı, 6/6 test geçti
- [x] Faz 1b: deployer'a ETH yüklendi
- [x] Faz 1c: deploy + Basescan verify — zincirde doğrulandı (`eth_getCode` dolu, `totalSupply` = 1.150.115)
- [x] Faz 2: cüzdan app — çoklu cüzdan + Face ID kilit (açılış+arka plan) + sistem teması + TR/EN otomatik (cihaz dili). Cüzdan listesi/seed'ler + adres defteri Keychain'de (app silinse kalıcı). Pencereler: Send/AddWallet tam ekran push (kenardan kayan), Receive/Import alttan sheet. Ekstra özellikler: bakiye gizle/göster, işlem geçmişi (Blockscout API, deploy sonrası dolar), adres defteri, AEIOT tanıtım kartı (toolbar sol üstteki info butonu → sheet), coin sparkles animasyonu. Hepsi simulator'da doğrulandı.
- [x] Faz 3: Uniswap v2 havuzu açıldı ($10 = 100k AEIOT + 0.0055 ETH). Swap sekmesi canlı — tüm çiftler (AEIOT/ETH/USDC/USDT/cbBTC) token-token dahil, WETH üzerinden çok-adımlı rota (`swapPath`: [A,WETH,B]). USDT (6 decimals) cüzdana + takasa eklendi, simulator'da 1000 AEIOT→0.167 USDT quote zincirle birebir doğrulandı.
