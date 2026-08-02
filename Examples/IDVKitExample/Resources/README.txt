Drop a CSCA master list here to enable chain-of-trust verification.

1. Download the German BSI master list (496 KB, 588 CSCAs, 114 countries):
   curl -L -o GermanMasterList.zip \
     "https://www.bsi.bund.de/SharedDocs/Downloads/DE/BSI/ElekAusweise/CSCA/GermanMasterList.zip?__blob=publicationFile&v=108"
   unzip GermanMasterList.zip

2. Copy the extracted master-list file into THIS folder, renamed with a .bin
   extension so Xcode treats it as a bundled resource (not source):
       GermanMasterList.bin

3. Regenerate the project and rebuild:
       xcodegen generate
       (then build/run in Xcode)

The example app auto-detects GermanMasterList.{ml,mls,bin,der,pem} in its bundle
and switches passive authentication to .enabled(cscaTrustStore:). With no file
present it stays in .integrityOnly mode (chain-of-trust = notPerformed).
