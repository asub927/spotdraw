cask "spotdraw" do
  version "1.0.0"
  sha256 "83cd19442177488a052159cb0725fa2e46dd204bc48bd493cbed8de00552bcad"

  url "https://github.com/asub927/spotdraw/releases/download/v#{version}/Spotdraw-#{version}.dmg"
  name "Spotdraw"
  desc "Native macOS screen annotation & presentation tool"
  homepage "https://github.com/asub927/spotdraw"

  depends_on macos: ">= :ventura"

  app "Spotdraw.app"

  zap trash: [
    "~/Library/Preferences/com.spotdraw.app.plist",
  ]
end
