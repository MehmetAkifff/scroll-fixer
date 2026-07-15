# Scroll Fixer

Diğer diller: [English](README.md)

Fare kaydırma yönünü düzelten küçük bir macOS menü çubuğu uygulaması.

**Trackpad ve fareyi aynı anda kullanıyorsanız** macOS ikisini de tek bir kaydırma yönüne mahkûm eder. "Natural scrolling" açıkken trackpad doğru his verir ama fare ters çalışır. Kapatınca tam tersi olur.

Scroll Fixer bunu çözer. Sistemdeki natural scrolling ayarına hiç dokunmadan, menü çubuğundaki tek bir anahtarla **sadece farenin** kaydırma yönünü ters çevirmenizi sağlar. Trackpad önceden nasıl çalışıyorsa öyle çalışmaya devam eder.

## Özellikler

- Menü çubuğunda tek bir anahtar. Fareye geçince aç, trackpad'e geçince kapat.
- Yalnızca fare kaydırma tekerini etkiler. Trackpad hareketleri asla değiştirilmez.
- Hiçbir sistem ayarını değiştirmez. macOS "natural scrolling" tercihiniz olduğu gibi kalır.
- Seçiminizi yeniden başlatmalar arasında hatırlar.
- Girişte otomatik başlar ve menü çubuğunda kalır.
- Hafif ve yerel. Swift/SwiftUI ile yazıldı; arka plan servisi ya da veri toplama yok.

## Gereksinimler

- macOS 26 (Tahoe) veya üzeri
- Apple Silicon veya Intel Mac

## Kurulum

1. [Releases](../../releases) sayfasından en son `Scroll Fixer.zip` dosyasını indirin.
2. Zip'i açın ve **Scroll Fixer.app**'i **Uygulamalar** klasörüne sürükleyin.
3. Çift tıklayıp açın. Uygulama Developer ID ile imzalı ve Apple tarafından notarize edilmiştir; hiçbir güvenlik uyarısı çıkmadan açılır.
4. İlk açılışta macOS **Erişilebilirlik** izni isteyecek. Bu, uygulamanın kaydırma olaylarını okuyup ters çevirebilmesi için gereklidir.
   - **Sistem Ayarları > Gizlilik ve Güvenlik > Erişilebilirlik** bölümünü açın.
   - **Scroll Fixer**'ı etkinleştirin.
   - Anahtar hemen etki etmezse uygulamadan çıkıp yeniden açın.

## Kullanım

- Menü çubuğundaki fare / el simgesini bulun.
- Tıklayınca anahtar açılır.
- **Anahtar açık** = fareyi kullanıyorsunuz, kaydırma yönü ters çevrilir.
- **Anahtar kapalı** = trackpad'i kullanıyorsunuz, hiçbir şey değiştirilmez.
- Küçük güç düğmesi uygulamadan çıkar.

Uygulamanın tamamı bu kadar. Bir kez ayarla, unut.

## Neden Erişilebilirlik izni gerekiyor

Farenin nasıl kaydıracağını değiştirmek için uygulama, kaydırma tekeri olaylarını izleyen düşük seviyeli bir event tap kurar ve anahtar açıkken bunları ters çevirir. macOS, sistem giriş olaylarını okuyan her uygulama için Erişilebilirlik izni ister. Scroll Fixer yalnızca kaydırma tekeri olaylarına ve yalnızca anahtar açıkken dokunur. Mac'inizden dışarı hiçbir şey göndermez.

## Kaynaktan derleme

Xcode kurulu olmalı.

```bash
git clone https://github.com/MehmetAkifff/scroll-fixer.git
cd scroll-fixer
xcodebuild -project mouseSwitcher.xcodeproj -scheme mouseSwitcher -configuration Release build
```

Ya da `mouseSwitcher.xcodeproj` dosyasını Xcode'da açıp Run'a basın.

Derlenen `Scroll Fixer.app`, Xcode'un DerivedData `Build/Products/Release` klasöründe olur. Kurmak için `/Applications` içine kopyalayın.

## Nasıl çalışır

Çekirdek kod [`ScrollManager.swift`](mouseSwitcher/ScrollManager.swift) içinde. Kaydırma tekeri olayları için bir `CGEvent` tap oluşturur. Anahtar açıkken gelen her kaydırma olayının tüm delta alanlarını okuyup negatiflerini geri yazar; böylece bir yöne kaydırma diğer yöne dönüşür. Anahtar kapalıyken olaylara dokunulmaz. Sistemin genel natural scrolling ayarı hiçbir zaman okunmaz veya değiştirilmez.

## Lisans

MIT. Bkz. [LICENSE](LICENSE).
