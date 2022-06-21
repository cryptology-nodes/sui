#!/bin/bash

sleep 1 && curl -s https://raw.githubusercontent.com/cryptology-nodes/main/main/logo.sh |  bash && sleep 2

echo -e '\n\e[100mChecking dependencies...\e[0m\n' && sleep 1

exists()
{
  command -v "$1" >/dev/null 2>&1
}

if exists curl; then
  echo ''
else
  sudo apt update && sudo apt install curl -y < /dev/null
fi

if exists jq; then
  echo ''
else
  sudo apt update && sudo apt install jq -y < /dev/null
fi

install_ufw() {
  curl -s https://cdn.qula.dev/common/ufw.sh | bash
}

install_ufw

bash_profile=$HOME/.bash_profile
sui_port=9889

if [ -f "$bash_profile" ]; then
    . $HOME/.bash_profile
fi

rm -rf /var/sui

mkdir -p /var/sui/db

cd $HOME

service_exists() {
    local n=$1
    if [[ $(systemctl list-units --all -t service --full --no-legend "$n.service" | sed 's/^\s*//g' | cut -f1 -d' ') == $n.service ]]; then
        return 0
    else
        return 1
    fi
}

echo -e '\n\e[100mDisabling previous \e[7msui-node\e[0m\e[100m service...\e[0m\n' && sleep 1

if service_exists sui-node; then
  systemctl stop sui-node
  systemctl disable sui-node
fi

echo -e '\n\e[100mDownloading node configuration...\e[0m\n' && sleep 1

wget -O /var/sui/fullnode.yaml  --no-verbose https://raw.githubusercontent.com/MystenLabs/sui/devnet/crates/sui-config/data/fullnode-template.yaml

echo -e '\n\e[100mDownloading genesis...\e[0m\n' && sleep 1
wget -O /var/sui/genesis.blob --no-verbose https://github.com/MystenLabs/sui-genesis/raw/main/devnet/genesis.blob

echo -e '\n\e[100mReplacing variables...\e[0m\n' && sleep 1
# Change db path, genesis to be in /var/sui + change ports
sed -i.dump "s|db-path:.*|db-path: \"\/var\/sui\/db\"|; s|genesis-file-location:.*|genesis-file-location: \"\/var\/sui\/genesis.blob\"|; s|json-rpc-address:.*|json-rpc-address: \"0.0.0.0:${sui_port}\"|" /var/sui/fullnode.yaml

echo -e '\n\e[100mDownloading \e[7msui-node\e[0m\e[100m binary...\e[0m\n' && sleep 1

# Download existing binary, faster than build
wget -O /var/sui/sui-node --no-verbose https://cdn.qula.dev/sui/sui-node
chmod +x /var/sui/sui-node
mv /var/sui/sui-node /usr/local/bin/sui-node

echo -e '\n\e[100mCreating \e[7msui-node\e[0m\e[100m service...\e[0m\n' && sleep 1
sudo tee << EOF >/dev/null /etc/systemd/system/sui-node.service
[Unit]
Description=SUI Full Node Service
After=network.target

[Service]
User=$USER
Type=simple
ExecStart=/usr/local/bin/sui-node --config-path /var/sui/fullnode.yaml
Restart=on-failure
RestartSec=1
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

sudo tee <<EOF >/dev/null /etc/systemd/journald.conf
Storage=persistent
EOF

echo -e '\n\e[100mStarting \e[7msui-node\e[0m\e[100m service...\e[0m\n' && sleep 1
sudo systemctl restart systemd-journald
sudo systemctl daemon-reload
sudo systemctl enable sui-node
sudo systemctl restart sui-node

echo "==================================================="
echo -e '\n\e[100mCheck Sui status\e[0m\n' && sleep 1
if [[ `service sui-node status | grep active` =~ "running" ]]; then
  echo -e "Your Sui Node \e[32minstalled and started\e[39m!"
  echo -e "You can check node status via the command \e[7mservice sui-node status\e[0m"
  echo -e "Press \e[7mQ\e[0m for exit from status menu"
  echo -e "You can check node logs via the command \e[7mjournalctl -u sui-node -f -n 10\e[0m"
else
  echo -e "Your Sui Node \e[31mwas not installed correctly\e[39m, please reinstall."
fi

healthcheck() {
  curl --write-out %{http_code} -s -X POST $1 -H 'Content-Type: application/json' -d '{ "jsonrpc":"2.0", "method":"rpc.discover","id":1}' --silent --output /dev/null
}

echo -e '\n\e[100mChecking Sui RPC status\e[0m\n' && sleep 10

status_code=$(healthcheck 127.0.0.1:${sui_port})
server_ip=$(dig +short myip.opendns.com @resolver1.opendns.com)

if [[ "$status_code" -ne 200 ]]; then
  echo -e "Your Sui RPC \e[31mdid not respond correctly\e[39m, try to run the following command:"
  echo -e "\e[31mcurl --write-out %{http_code} -s -X POST 127.0.0.1:${sui_port} -H 'Content-Type: application/json' -d '{ "jsonrpc":"2.0", "method":"rpc.discover","id":1}' \e[39m"
else
  echo -e '\n\e[100mSui RPC works correctly \e[0m\n' && sleep 1
fi

echo -e "\n\e[100mYour Sui RPC is located: ${server_ip}:${sui_port} \e[0m\n" && sleep 1

