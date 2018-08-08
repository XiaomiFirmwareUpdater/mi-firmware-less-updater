#!/bin/bash
#Check if db exist
if [ -e miuiversion ]
then
    mv miuiversion miuiversion_old
else
    echo "DB not found!"
fi

#Download
curl -H "PRIVATE-TOKEN: $GITLAB_OAUTH_TOKEN_VE" 'https://gitlab.com/api/v4/projects/7746867/repository/files/getversion.sh/raw?ref=master' -o getversion.sh && chmod +x getversion.sh

#Fetch
echo Fetching updates:
cat device | while read device; do
codename=$(echo $device | cut -d , -f1)
android=$(echo $device | cut -d , -f2)
id=$(echo $device | cut -d , -f3)
tmpname=$(echo $device | cut -d , -f1 | sed 's/_/-/g')
url=`./getversion.sh $codename X $android`
echo $tmpname"="$url >> raw_out
sed -i 's/param error/not avilable/g' ./raw_out
done
cat raw_out | sort | sed 's/http.*miui_//' | cut -d _ -f1,2 | sed 's/-/_/g' > miuiversion

#Compare
echo Comparing:
cat miuiversion | while read rom; do
	codename=$(echo $rom | cut -d = -f1)
	new=`cat miuiversion | grep $codename | cut -d = -f2`
	old=`cat miuiversion_old | grep $codename | cut -d = -f2`
	diff <(echo "$old") <(echo "$new") | grep ^"<\|>" >> compare
done
awk '!seen[$0]++' compare > changes

#Info
if [ -s changes ]
then
	echo "Here's the new updates!"
	cat changes | grep ">" | cut -d ">" -f2 | sed 's/ //g' 2>&1 | tee updates
else
    echo "No changes found!"
fi

#Downloads
if [ -s updates ]
then
    echo "Download Links!"
	for rom in `cat updates`; do cat raw_out | grep $rom | cut -d = -f2; done 2>&1 | tee dl_links
else
    echo "No new updates!"
fi

#Start
wget -qq --progress=bar https://github.com/XiaomiFirmwareUpdater/xiaomi-flashable-firmware-less-creator/raw/master/create_flashable_firmware-less.sh && chmod +x create_flashable_firmware-less.sh
cat dl_links | while read link; do
dl=$(echo $link | cut -d = -f2)
zip=$(echo $dl | cut -d / -f5)
ver=$(echo $zip | cut -d _ -f3)
echo Downloading $zip
wget -qq --progress=bar $dl
mkdir -p changelog/$ver/
./create_flashable_firmware-less.sh $zip
rm $zip; done

#Upload
echo Uploading Files:
for file in *.zip; do product=$(echo $file | cut -d _ -f2); version=$(echo $file | cut -d _ -f5); wput $file ftp://$afhuser:$afhpass@uploads.androidfilehost.com//Xiaomi-Firmware/firmware-less/$product/$version/ ; done

#Push
echo Pushing:
git config --global user.email "$gitmail" ; git config --global user.name "$gituser"
git add miuiversion ; git commit -m "Sync: $(date +%d.%m.%Y)"
git push -q https://$GIT_OAUTH_TOKEN_XFU@github.com/XiaomiFirmwareUpdater/$repo.git HEAD:$branch

#Telegram
wget -q https://github.com/yshalsager/telegram.sh/raw/master/telegram && chmod +x telegram
if [ -s dl_links ]
then
for file in *.zip; do 
	codename=$(echo $file | cut -d _ -f2)
	model=$(echo $file | cut -d _ -f4)
	version=$(echo $file | cut -d _ -f5)
	android=$(echo $file | cut -d _ -f7 | cut -d . -f1,2)
	size=$(du -h $file | awk '{print $1}')
	md5=$(md5sum $file | awk '{print $1}')
	./telegram -t $bottoken -c @XiaomiFirmwareUpdater -M "New firmware-less update available!
	*Device*: $model
	*Codename*: $codename
	*Version*: $version
	*Android*: $android
	Filename: *$file*
	*Filesize*: $size
	*MD5*: $md5
	*Download Links*:
	[Sourceforge](https://sourceforge.net/projects/xiaomi-firmware-updater/files/firmware-less/$codename/$version/)
	@XiaomiFirmwareUpdater | @MIUIUpdatesTracker"
done
else
    echo "Nothing found!"
fi

#Cleanup
rm raw_out compare changes updates dl_links 2> /dev/null
