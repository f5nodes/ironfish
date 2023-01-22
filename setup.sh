#!/bin/bash
exists()
{
  command -v "$1" >/dev/null 2>&1
}

service_exists() {
    local n=$1
    if [[ $(systemctl list-units --all -t service --full --no-legend "$n.service" | sed 's/^\s*//g' | cut -f1 -d' ') == $n.service ]]; then
        return 0
    else
        return 1
    fi
}

if exists curl; then
	echo ''
else
  sudo apt install curl -y < "/dev/null"
fi
bash_profile=$HOME/.bash_profile
if [ -f "$bash_profile" ]; then
    . $HOME/.bash_profile
fi

function setupVars {
	if [ ! $IRONFISH_WALLET ]; then
		read -p "Вкажіть назву гаманця: " IRONFISH_WALLET
		echo 'export IRONFISH_WALLET='${IRONFISH_WALLET} >> $HOME/.bash_profile
	fi
	echo -e '\n\e[42mВаша назва гаманця:' $IRONFISH_WALLET '\e[0m\n'
	if [ ! $IRONFISH_NODENAME ]; then
		read -p "Вкажіть назву ноди: " IRONFISH_NODENAME
		echo 'export IRONFISH_NODENAME='${IRONFISH_NODENAME} >> $HOME/.bash_profile
	fi
	echo -e '\n\e[42mВаша назва ноди:' $IRONFISH_NODENAME '\e[0m\n'
	if [ ! $IRONFISH_THREADS ]; then
		read -e -p "Вкажіть кількість потоків [-1]: " IRONFISH_THREADS
		echo 'export IRONFISH_THREADS='${IRONFISH_THREADS:--1} >> $HOME/.bash_profile
	fi
	echo -e '\n\e[42mВаша кількість потоків:' $IRONFISH_THREADS '\e[0m\n'
	echo 'source $HOME/.bashrc' >> $HOME/.bash_profile
	. $HOME/.bash_profile
	sleep 1
}

function installSnapshot {
	echo -e '\n\e[42mInstalling snapshot...\e[0m\n' && sleep 1
	systemctl stop ironfishd
	sleep 5
	ironfish chain:download --confirm
	sleep 3
	systemctl restart ironfishd
}

function setupSwap {
	echo -e '\n\e[42mSet up swapfile\e[0m\n'
	curl -s https://api.nodes.guru/swap4.sh | bash
}

function backupWallet {
	echo -e '\n\e[42mPreparing to backup default wallet...\e[0m\n' && sleep 1
	echo -e '\n\e[42mYou can just press enter if you want backup your default wallet\e[0m\n' && sleep 1
	read -e -p "Вкажіть назву гаманця [default]: " IRONFISH_WALLET_BACKUP_NAME
	IRONFISH_WALLET_BACKUP_NAME=${IRONFISH_WALLET_BACKUP_NAME:-default}
	cd $HOME/ironfish/ironfish-cli/
	mkdir -p $HOME/.ironfish/keys
	ironfish accounts:export $IRONFISH_WALLET_BACKUP_NAME $HOME/.ironfish/keys/$IRONFISH_WALLET_BACKUP_NAME.json
	echo -e '\n\e[42mВаш key file:\e[0m\n' && sleep 1
	walletBkpPath="$HOME/.ironfish/keys/$IRONFISH_WALLET_BACKUP_NAME.json"
	cat $HOME/.ironfish/keys/$IRONFISH_WALLET_BACKUP_NAME.json
	echo -e "\n\nImport command:"
	echo -e "\e[7mironfish accounts:import $walletBkpPath\e[0m"
	cd $HOME
}

function installDeps {
	echo -e '\n\e[42mПідготовка до встановлення\e[0m\n' && sleep 1
	cd $HOME
	sudo apt update
	sudo curl https://sh.rustup.rs -sSf | sh -s -- -y
	. $HOME/.cargo/env
	curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
	sudo apt update
	sudo apt install curl make clang pkg-config libssl-dev build-essential git jq nodejs -y < "/dev/null"
	sudo apt install npm
}

function createConfig {
	mkdir -p $HOME/.ironfish
	echo "{
		\"nodeName\": \"${IRONFISH_NODENAME}\",
		\"blockGraffiti\": \"${IRONFISH_NODENAME}\"
	}" > $HOME/.ironfish/config.json
	systemctl restart ironfishd ironfishd-miner
}

function installSoftware {
	. $HOME/.bash_profile
	. $HOME/.cargo/env
	echo -e '\n\e[42mInstall software\e[0m\n' && sleep 1
	rm -rf ~/.ironfish/databases
	cd $HOME
	npm install -g ironfish
}

function updateSoftware {
	if service_exists ironfishd-pool; then
		sudo systemctl stop ironfishd-pool
	fi
	sudo systemctl stop ironfishd ironfishd-miner
	. $HOME/.bash_profile
	. $HOME/.cargo/env
	cp -r $HOME/.ironfish/accounts $HOME/ironfish_accounts_$(date +%s)
	echo -e '\n\e[42mUpdate software\e[0m\n' && sleep 1
	cd $HOME
	npm update -g ironfish
}

function installService {
echo -e '\n\e[42mRunning\e[0m\n' && sleep 1
echo -e '\n\e[42mCreating a service\e[0m\n' && sleep 1

echo "[Unit]
Description=IronFish Node
After=network-online.target
[Service]
User=$USER
ExecStart=$(which ironfish) start
Restart=always
RestartSec=10
LimitNOFILE=10000
[Install]
WantedBy=multi-user.target
" > $HOME/ironfishd.service
echo "[Unit]
Description=IronFish Miner
After=network-online.target
[Service]
User=$USER
ExecStart=$(which ironfish) miners:start -v -t $IRONFISH_THREADS --no-richOutput
Restart=always
RestartSec=10
LimitNOFILE=10000
[Install]
WantedBy=multi-user.target
" > $HOME/ironfishd-miner.service
sudo mv $HOME/ironfishd.service /etc/systemd/system
sudo mv $HOME/ironfishd-miner.service /etc/systemd/system
sudo tee <<EOF >/dev/null /etc/systemd/journald.conf
Storage=persistent
EOF
sudo systemctl restart systemd-journald
sudo systemctl daemon-reload
echo -e '\n\e[42mЗапуск сервісу\e[0m\n' && sleep 1
sudo systemctl enable ironfishd ironfishd-miner
sudo systemctl restart ironfishd ironfishd-miner
echo -e '\n\e[42mПеревірити статус ноди\e[0m\n' && sleep 1
if [[ `service ironfishd status | grep active` =~ "running" ]]; then
  echo -e "Ваша IronFish нода \e[32mвстановленя та працює\e[39m!"
  echo -e "Перевірити статус Вашої ноди можна командою \e[7mservice ironfishd status\e[0m"
  echo -e "Натисніть \e[7mQ\e[0m щоб вийти з статус меню"
else
  echo -e "Ваша IronFish нода \e[31mбула встановлена неправильно\e[39m, виконайте перевстановлення."
fi
if [[ `service ironfishd-miner status | grep active` =~ "running" ]]; then
  echo -e "Ваш IronFish майнер \e[32mвстановлений та працює\e[39m!"
  echo -e "Перевірити статус Вашого майнеру можна командою \e[7mservice ironfishd-miner status\e[0m"
  echo -e "Натисніть \e[7mQ\e[0m щоб вийти з статус меню"
else
  echo -e "Ваш IronFish майнер \e[31mбув встановлена неправильно\e[39m, виконайте перевстановлення."
fi
. $HOME/.bash_profile
}
function deleteIronfish {
	sudo systemctl disable ironfishd ironfishd-miner
	sudo systemctl stop ironfishd ironfishd-miner 
	sudo rm -rf $HOME/ironfish $HOME/.ironfish $(which ironfish)
}

function installAutoAssets() {
	crontab -r
	rm -rf $HOME/ironfish-auto
	mkdir $HOME/ironfish-auto

	read -p "Вкажіть свою пошту: " IRONFISH_EMAIL
	(crontab -l; echo "0 0 * * * echo $IRONFISH_EMAIL | ironfish faucet | tee -i $HOME/ironfish-auto/faucet.log") | crontab -
	
	apt install bc -y
	wget -q -O $HOME/ironfish-auto/assets.sh https://raw.githubusercontent.com/cyberomanov/ironfish-mbs/main/bms.sh # thanks @cyberomanov
	chmod u+x $HOME/ironfish-auto/assets.sh
	(crontab -l; echo "0 0 * * 5 $HOME/ironfish-auto/assets.sh | tee -i $HOME/ironfish-auto/assets.log") | crontab -

	echo -e "\nAuto-Faucet & Auto-Assets скрипт \e[92mвстановлений\e[39m"
	echo -e "Auto-Faucet \e[92mкожен день 00:00\e[0m, Auto-Assets \e[92mкожна п'ятниця 00:00\e[0m"
	echo -e "Подивитись логи \e[92mtail -f ironfish-auto/faucet.log\e[0m та \e[92mtail -f ironfish-auto/assets.log\e[0m\n"
	echo -e "by \e[92mt.me/f5nodes\e[0m / \e[92mf5nodes.com\e[0m\n"
}


PS3='Вкажіть Ваш вибір (введіть номер опції та натисніть Enter): '
options=("Install" "Upgrade" "Backup wallet" "Install snapshot" "Delete node" "Install Auto-Assets" "Quit")
select opt in "${options[@]}"
do
    case $opt in
        "Install")
           echo -e '\n\e[42mВстановлення...\e[0m\n' && sleep 1
			setupVars
			setupSwap
			installDeps
			installSoftware
			installService
			createConfig
			break
            ;;
        "Upgrade")
            echo -e '\n\e[33mОновлення...\e[0m\n' && sleep 1
			setupVars
			updateSoftware
			installService
			echo -e '\n\e[33mНода оновлена!\e[0m\n' && sleep 1
			break
            ;;
		"Backup wallet")
			echo -e '\n\e[33mБекап гаманця...\e[0m\n' && sleep 1
			backupWallet
			echo -e '\n\e[33mВаш гаманець збережений в $HOME/.ironfish/keys папці!\e[0m\n' && sleep 1
			break
            ;;
		 "Install snapshot")
			echo -e '\n\e[33mВстанолення снапшоту...\e[0m\n' && sleep 1
			installSnapshot
			echo -e '\n\e[33mСнапшот встановлений, нода запущена.\e[0m\n' && sleep 1
			break
			;;
		"Delete node")
			echo -e '\n\e[31mВидалення...\e[0m\n' && sleep 1
			deleteIronfish
			echo -e '\n\e[42mIronfish видалений!\e[0m\n' && sleep 1
			break
            ;;
		"Install Auto-Assets")
			echo -e '\n\e[31mВстановлення Auto-Assets...\e[0m\n' && sleep 1
			installAutoAssets
			break
            ;;
        "Quit")
            break
            ;;
        *) echo -e "\e[91mПомилка опції $REPLY\e[0m";;
    esac
done