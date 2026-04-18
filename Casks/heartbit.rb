cask "heartbit" do
  version "1.3.4"
  sha256 "f3665e70a0074f43246b9b2cd99e13ecbee4fdfde2d71ef7d5ce26a5c8e5a1a9"

  url "https://github.com/ivans3m/homebrew-HeartBit/releases/download/v#{version}/HeartBit-v#{version}.zip"
  name "HeartBit"
  desc "Menu bar task runner for scheduled scripts, apps, and shell commands"
  homepage "https://github.com/ivans3m/homebrew-HeartBit"

  depends_on macos: ">= :sonoma"

  app "HeartBit.app"

  zap trash: [
    "~/Library/Logs/HeartBit",
    "~/Library/Preferences/com.s3m.HeartBit.plist",
  ]
end
