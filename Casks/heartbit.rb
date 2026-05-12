cask "heartbit" do
  version "1.5.0"
  sha256 "153543da9101bef447088424e075202aad04c70ab57e7d51c986e4dffa146edd"

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
