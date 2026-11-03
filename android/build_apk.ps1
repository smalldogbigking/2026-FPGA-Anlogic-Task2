param([string]$Sdk=$env:ANDROID_HOME,[string]$Jdk=$env:JAVA_HOME)
$ErrorActionPreference='Stop'
if (!$Sdk) { $Sdk=$env:ANDROID_SDK_ROOT }
if (!$Sdk -or !$Jdk) { throw 'Set ANDROID_HOME and JAVA_HOME, or pass -Sdk and -Jdk.' }
$Sdk=(Resolve-Path -LiteralPath $Sdk).Path
$Jdk=(Resolve-Path -LiteralPath $Jdk).Path
$root=$PSScriptRoot
$build=Join-Path $root ('build/'+(Get-Date -Format 'yyyyMMdd_HHmmss'))
$tools=Join-Path $Sdk 'build-tools/36.0.0'
$androidJar=Join-Path $Sdk 'platforms/android-36.1/android.jar'
$java=Join-Path $Jdk 'bin/java.exe'
$javac=Join-Path $Jdk 'bin/javac.exe'
$signing=Join-Path $root 'signing'
$release=Join-Path $root 'releases'
New-Item -ItemType Directory -Force -Path $build,"$build/gen","$build/classes","$build/dex",$signing,$release | Out-Null
$webAssets=Join-Path $root 'assets/web'
New-Item -ItemType Directory -Force -Path $webAssets | Out-Null
foreach($asset in @('style.css','app.js','events.js','anlogic.png')){
 $source=Join-Path $root "../pc_bs/static/$asset"
 if(Test-Path -LiteralPath $source){Copy-Item -LiteralPath $source -Destination (Join-Path $webAssets $asset)}
 elseif(!(Test-Path -LiteralPath (Join-Path $webAssets $asset))){throw "Missing bundled web asset: $asset"}
}
function Check-Step($name){if($LASTEXITCODE -ne 0){throw "Android build failed: $name"}}
& "$tools/aapt2.exe" compile --dir "$root/res" -o "$build/resources.zip"
Check-Step 'resource compile'
& "$tools/aapt2.exe" link --manifest "$root/AndroidManifest.xml" -I $androidJar -A "$root/assets" --java "$build/gen" --min-sdk-version 26 --target-sdk-version 36 -o "$build/resources.apk" "$build/resources.zip"
Check-Step 'resource link'
$sources=@(Get-ChildItem "$root/src","$build/gen" -Recurse -Filter '*.java' | ForEach-Object {$_.FullName})
& $javac -source 8 -target 8 -Xlint:-options -bootclasspath "$androidJar;$tools/core-lambda-stubs.jar" -encoding UTF-8 -d "$build/classes" @sources
Check-Step 'Java compile'
& "$Jdk/bin/jar.exe" cf "$build/classes.jar" -C "$build/classes" .
Check-Step 'class archive'
& $java -cp "$tools/lib/d8.jar" com.android.tools.r8.D8 --lib $androidJar --min-api 26 --output "$build/dex" "$build/classes.jar"
Check-Step 'DEX compile'
$env:FPGA_APK_BUILD=$build
@'
from pathlib import Path
import os,zipfile
p=Path(os.environ['FPGA_APK_BUILD'])
with zipfile.ZipFile(p/'resources.apk') as source,zipfile.ZipFile(p/'unsigned.apk','w') as z:
 for item in source.infolist():
  data=source.read(item)
  z.writestr(item,data)
 for d in (p/'dex').glob('*.dex'):z.write(d,d.name,compress_type=zipfile.ZIP_DEFLATED)
'@ | python -
Check-Step 'APK package'
& "$tools/zipalign.exe" -P 16 -f 4 "$build/unsigned.apk" "$build/aligned.apk"
Check-Step 'ZIP align'
$password=Join-Path $signing 'password.txt'
$key=Join-Path $signing 'fpga-vision-release.p12'
if(!(Test-Path $key)){
 $bytes=[byte[]]::new(32);$rng=[Security.Cryptography.RandomNumberGenerator]::Create(); try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
 [IO.File]::WriteAllText($password,[Convert]::ToBase64String($bytes),[Text.UTF8Encoding]::new($false))
 & "$Jdk/bin/keytool.exe" -genkeypair -keystore $key -storetype PKCS12 -storepass:file $password -keypass:file $password -alias fpga-vision -keyalg RSA -keysize 3072 -validity 10000 -dname 'CN=FPGA Vision Local, OU=Project, O=FPGA Vision, C=CN'
 Check-Step 'signing key'
}
& $java -jar "$tools/lib/apksigner.jar" sign --v4-signing-enabled false --ks $key --ks-key-alias fpga-vision --ks-pass "file:$password" --out "$release/FPGA-Vision.apk" "$build/aligned.apk"
Check-Step 'APK sign'
& $java -jar "$tools/lib/apksigner.jar" verify --verbose --print-certs "$release/FPGA-Vision.apk" | Set-Content "$release/signature-verification.txt"
Check-Step 'APK signature verification'
& "$tools/aapt.exe" dump badging "$release/FPGA-Vision.apk" | Set-Content "$release/package-info.txt"
Check-Step 'APK manifest verification'
$manifestXml=[xml](Get-Content "$root/AndroidManifest.xml")
$versionName=$manifestXml.manifest.GetAttribute('versionName','http://schemas.android.com/apk/res/android')
Copy-Item -LiteralPath "$release/FPGA-Vision.apk" -Destination "$release/Anlogic-Vision-v$versionName.apk"
$releaseInfo=@{version_name=$versionName;version_code=[int]$manifestXml.manifest.GetAttribute('versionCode','http://schemas.android.com/apk/res/android');versioned_file="Anlogic-Vision-v$versionName.apk";file='FPGA-Vision.apk';sha256=(Get-FileHash "$release/FPGA-Vision.apk" -Algorithm SHA256).Hash.ToLower()}
$releaseInfo | ConvertTo-Json | Set-Content -LiteralPath "$release/release.json" -Encoding utf8
Get-FileHash "$release/FPGA-Vision.apk" -Algorithm SHA256 | Format-List
Write-Output "APK ready: $release/FPGA-Vision.apk"
