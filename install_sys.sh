#!/bin/bash

# TODO redirect output
dry_run=${dry_run:-false}
output=${output:-/tmp/arch-install-logs}
while getopts d:o: option
do
    case "${option}"
        in
        d) dry_run=${OPTARG};;
        o) output=${OPTARG};;
    esac
done

pacman -Sy
pacman --noconfirm -S dialog

dialog --defaultno \
    --title "Are you sure?" \
    --yesno "This is my personnal arch linux install. \n\n\
    It will just DESTROY EVERYTHING on the hard disk of your choice. \n\n\
    Don't say YES if you are not sure about what your are doing! \n\n\
    Are you sure?"  15 60 || exit

dialog --no-cancel --inputbox "Enter a name for your computer." 10 60 2> comp

devices_list=($(lsblk -d | awk '{print "/dev/" $1 " " $4 " off"}' | grep -E 'sd|hd|vd|nvme|mmcblk' | sed "s/off/on/"))
dialog --title "Choose your hard drive" --no-cancel --radiolist \
    "Where do you want to install your new system?\n\n\
    Select with SPACE, valid with ENTER.\n\n\
    WARNING: Everything will be DESTROYED on the hard disk!" 15 60 4 ${devices_list[@]} 2> hd
hd=$(cat hd); rm hd

default_size="8"
dialog --no-cancel --inputbox "You need four partitions: Boot, Root and Swap \n\
    The boot will be 512M\n\
    The root will be the rest of the hard disk\n\
    Enter partitionsize in gb for the Swap. \n\n\
    If you dont enter anything: \n\
        swap -> ${default_size}G \n\n" 20 60 2> swap_size
size=$(cat swap_size) && rm swap_size

[[ $size =~ ^[0-9]+$ ]] || size=$default_size

dialog --no-cancel \
    --title "!!! DELETE EVERYTHING !!!" \
    --menu "Choose the way to destroy everything on your hard disk ($hd)" 15 60 4 \
    1 "Use dd (wipe all disk)" \
    2 "Use schred (slow & secure)" \
    3 "No need - my hard disk is empty" 2> eraser

hderaser=$(cat eraser); rm eraser

function eraseDisk() {
    case $1 in
        1) dd if=/dev/zero of=$hd status=progress 2>&1 | dialog --title "Formatting $hd..." --progressbox --stdout 20 60;;
        2) shred -v $hd | dialog --title "Formatting $hd..." --progressbox --stdout 20 60;;
        3) ;;
    esac
}

if [[ "$dry_run" = false ]]; then
    eraseDisk $hderaser
    timedatectl set-ntp true
fi

if [[ "$dry_run" = false ]]; then
#g - create non empty GPT partition table
#n - create new partition
#p - primary partition
#e - extended partition
#w - write the table to disk and exit
cat <<EOF | fdisk $hd
g
n


+512M
t
4
n


+${size}G
n



w
EOF
partprobe

mkswap "${hd}2"
swapon "${hd}2"

mkfs.ext4 "${hd}3"
mount "${hd}3" /mnt

# home
# mkfs.ext4 "${hd}4"
# mkdir /mnt/home
# mount "${hd}4" /mnt/home

# dialog --infobox "Encrypt /home partition..." 4 40

# mkdir /mnt/etc/
# mkdir -m 700 /mnt/etc/luks-keys
# dd if=/dev/random of=/mnt/etc/luks-keys/home bs=1 count=256
# cat << EOF | cryptsetup --cipher aes-xts-plain64\
#     --key-size 512\
#     --hash sha512\
#     --iter-time 5000\
#     --use-random\
#     luksFormat\
#     /dev/sda4 \
#     /mnt/etc/luks-keys/home
# YES
# EOF

# cryptsetup -d /mnt/etc/luks-keys/home open /dev/sda4 home

# mkfs.ext4 /dev/mapper/home
# mkdir /mnt/home
# mount /dev/mapper/home /mnt/home

cat comp > /mnt/etc/hostname && echo "127.0.0.1    $(cat comp).localdomain $(cat comp)" >> /etc/hosts && rm comp

pacstrap /mnt base base-devel linux linux-firmware

genfstab -U /mnt >> /mnt/etc/fstab

### Continue installation
curl https://raw.githubusercontent.com/Phantas0s/ArchInstall/master/install_chroot.sh > /mnt/install_chroot.sh
arch-chroot /mnt bash install_chroot.sh
rm /mnt/install_chroot.sh

fi

dialog --title "Reboot time" \
    --yesno "Congrats! The install is done! \n\nTo run the new graphical environment, you need to restart your computer. \n\nDo you want to restart now?" 20 60

response=$?
case $response in
    0) reboot;;
    1) clear;;
esac

clear
