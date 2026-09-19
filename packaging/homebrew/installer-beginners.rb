class InstallerBeginners < Formula
  desc "Simple package installer for beginners"
  homepage "https://github.com/S00what/installer-beginners"
  url "https://github.com/S00what/installer-beginners/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "REPLACE_WITH_SHA256"
  license "GPL-3.0-or-later"

  depends_on "bash"

  def install
    system "make", "install", "PREFIX=#{prefix}"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/installer-beginners --version")
  end
end
