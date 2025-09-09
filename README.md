FOR MACOS:
# If you don't have Homebrew, install it (optional):
/bin/bash -c “$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)”

brew update
brew reinstall go

# Make sure GOPATH/bin is in your PATH (for tools you install with `go install`)
echo ‘export PATH="$PATH:$(go env GOPATH)/bin"’ >> ~/.zshrc
source ~/.zshrc

FOR LINUX: 
sudo apt update && sudo apt install -y git curl jq build-essential
# Install go
GO_VERSION=$(curl -s https://go.dev/VERSION?m=text | head -n1)
curl -LO https://go.dev/dl/${GO_VERSION}.linux-amd64.tar.gz
sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf ${GO_VERSION}.linux-amd64.tar.gz
echo 'export PATH="$PATH:/usr/local/go/bin:$HOME/go/bin"' >> ~/.zshrc && source ~/.zshrc



INSTALL TOOLS: 

go install github.com/tomnomnom/assetfinder@latest
go install github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest
go install github.com/lc/gau/v2/cmd/gau@latest
go install github.com/projectdiscovery/dnsx/cmd/dnsx@latest
go install github.com/projectdiscovery/httpx/cmd/httpx@latest


HOW TO USE: 

chmod +x recon.sh

# Single domain
./recon.sh -u ejemplo.com

# List (One per line)
./recon.sh -l targets.txt

