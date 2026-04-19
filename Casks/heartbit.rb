cask "heartbit" do
  version "1.4.0"
  sha256 "a24d5da76413be2477e5d0173f98752089fa06e706e7edb5b5c0f9610567ba37"

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
