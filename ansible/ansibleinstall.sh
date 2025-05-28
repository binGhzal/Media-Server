sudo apt update
sudo apt install pipx -y
pipx ensurepath --global # optional to allow pipx actions with --global argument
pipx install argcomplete
echo 'eval "$(register-python-argcomplete pipx)"' >> ~/.bashrc
pipx install --include-deps ansible
pipx upgrade --include-injected ansible
pipx inject ansible argcomplete
pipx inject --include-apps ansible argcomplete
