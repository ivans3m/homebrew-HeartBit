cask "heartbit" do
  version "1.4.1"
  sha256 "12e03919e294d31d3466d95f73f75b693d582a2781dadba8637f5c0635ed6fc6"

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
