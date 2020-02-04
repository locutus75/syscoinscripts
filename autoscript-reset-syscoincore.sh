sudo service syscoind stop
sleep 20
cp /home/syscoin/.syscoin/syscoin.conf /home/syscoin/syscoin.org
rm -rf /home/syscoin/.syscoin
mkdir /home/syscoin/.syscoin
cp /home/syscoin/syscoin.org /home/syscoin/.syscoin/syscoin.conf
chown -R syscoin /home/syscoin/.syscoin
sleep 10
sudo service syscoind start
