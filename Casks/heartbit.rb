cask "heartbit" do
  version "1.4.0"
  sha256 "048c0679d6c05dc258b891c811cc7e60e4c8aa3c66e025ed6ffc3aaf8e4be877"

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
