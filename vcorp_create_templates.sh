#!/bin/bash

openwrt_url='https://mirror-03.infra.openwrt.org/releases/24.10.3/targets/x86/64/openwrt-24.10.3-x86-64-generic-ext4-combined.img.gz'
debian_url='https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-13.1.0-amd64-netinst.iso'
openwrt_vdi_checksum="cc621a8a8a2b780d3c8f47ce3ecb2ba59e4a0cff1ebeb8d096d7c7e0202799c7"
debian_iso_checksum="658b28e209b578fe788ec5867deebae57b6aac5fce3692bbb116bab9c65568b3"
vcorp_group="VCorp"
debian_iso_filename=$(basename $debian_url)
openwrt_zipped_file=$(basename $openwrt_url)
openwrt_file=${openwrt_zipped_file%.gz}
openwrt_vmname="openwrt_template"
srv_template_vmname='debian_server_template'
desktop_template_vmname='debian_desktop_template'
idkeys_path="$HOME/.ssh/vcorp_sysadmin"
sysadmin_user="sysadmin"
iso_dir=""
is_wsl=0
is_darwin=0
vbox=
default_vm_location=
wsl_default_vm_location=
download_folder=
openwrt_vm_path=
wsl_download_folder=
open_wrt_file_path=
wsl_openwrt_vm_path=
vdi_path=
wsl_vbox_templates_path=
old_protocol=
ip_vm=


check_platform() {

    if grep -q microsoft /proc/version 2> /dev/null; then
        is_wsl=1
    fi

    if (( is_wsl )); then
        # Estem en entorn WSL
        echo "Configurant per entorn WSL..."
        vbox="/mnt/c/Program Files/Oracle/VirtualBox/VBoxManage.exe"
        default_vm_location="/mnt/c/VirtualCorp"
        wsl_default_vm_location="C:\\VirtualCorp"
        download_folder="/mnt/c/TEMP"
        openwrt_vm_path="$default_vm_location/$vcorp_group/templates/"

        wsl_download_folder="c:\\TEMP"
        open_wrt_file_path="$wsl_download_folder\\$openwrt_file"

        wsl_openwrt_vm_path="$wsl_default_vm_location\\$vcorp_group\\templates\\$openwrt_vmname"
        vdi_path="$wsl_openwrt_vm_path\\openwrt.vdi"

        # vbox_vcorp_path="$HOME/VirtualBox VMs/VCorp"
        # vbox_templates_path="$vbox_vcorp_path/templates"
        wsl_vbox_templates_path="$wsl_default_vm_location\\$vcorp_group\\templates"
        old_protocol=''
        ip_vm=172.20.224.1


    else 
        if [[ $(uname -s) == "Darwin" ]]; then
            is_darwin=1
        fi
        # Estem en entorn MacOS o Linux natiu
        echo "Configurant per entorn Linux natiu o MacOS..."
        vbox="vboxmanage"
        default_vm_location="$HOME/VirtualBox VMs"
        wsl_default_vm_location="$HOME/VirtualBox VMs"
        download_folder=
        openwrt_vm_path="$default_vm_location/$vcorp_group/templates"

        wsl_download_folder="$download_folder"
        open_wrt_file_path="$wsl_download_folder/$openwrt_file"

        wsl_openwrt_vm_path="$openwrt_vm_path/$openwrt_vmname"
        vdi_path="$wsl_openwrt_vm_path/openwrt.vdi"

        # vbox_vcorp_path="$HOME/VirtualBox VMs/VCorp"
        # vbox_templates_path="$vbox_vcorp_path/templates"
        wsl_vbox_templates_path="$openwrt_vm_path"
        old_protocol='-O'
        ip_vm=localhost

    fi
}

custom_iso_dir() {
    if [ ! -d "$iso_dir" ]; then #
        echo "ISOs Directory $iso_dir does not exist. Creating..."
        mkdir -p "$iso_dir" || { echo "Couldn't create $iso_dir"; exit 1; }
    fi
    download_folder="$iso_dir"
    echo "ISOs will be managed here: $download_folder"
}

ensure_dirs() {
    mkdir -p "$default_vm_location"
    "$vbox" setproperty machinefolder "$wsl_default_vm_location"
}

create_openwrtvdi() {
        # $1 path to decompress debian iso
    echo "Checking OpenWRT Image in local filesystem..."
    existing_img=$(find "$download_folder" -name "$openwrt_zipped_file" -maxdepth 1 2> /dev/null | head -1)
    img_path=$(dirname $existing_img 2> /dev/null)
    if [[ -n $img_path ]]
    then
        download_folder=$img_path
        echo "Img found at: $download_folder/$openwrt_zipped_file"
    fi
    
    [[ -n $img_path ]] || wget -P "$download_folder" "$openwrt_url"
    if [[ $(sha256sum "$download_folder/$openwrt_zipped_file" | cut -d' ' -f1) != "$openwrt_vdi_checksum" ]]
    then
        echo "Bad OpenWRT IMG!"
        exit 1
    fi
    gzip -fd "$download_folder/$openwrt_zipped_file"

    mkdir "$download_folder/openwrtmnt" 2> /dev/null
    type=ext4
    if (( is_darwin )); then
        type=hfsplus
    fi
    sudo mount -t $type -o offset=17301504 "$download_folder/$openwrt_file" "$download_folder/openwrtmnt"
    ls "$download_folder/openwrtmnt"
    config_openwrt_network
    sudo umount "$download_folder/openwrtmnt"

    mkdir -p "$openwrt_vm_path/$openwrt_vmname"

    rm -f "$openwrt_vm_path/openwrt.vdi"

    "$vbox" convertfromraw --format VDI "$download_folder/$openwrt_file" "$vdi_path"
}

config_openwrt_network() {

    cat "$idkeys_path.pub" | sudo tee "$download_folder/openwrtmnt/etc/dropbear/authorized_keys"
    sudo chmod 644 "$download_folder/openwrtmnt/etc/dropbear/authorized_keys"

    sudo sed -i "s|root::|root:$(openssl passwd -1 'Asdqwe!23'):|g" "$download_folder/openwrtmnt/etc/shadow"

    cat <<EOF | sudo tee "$download_folder/openwrtmnt/etc/config/network"
config interface 'loopback'
        option device 'lo'
        option proto 'static'
        option ipaddr '127.0.0.1'
        option netmask '255.0.0.0'

config globals 'globals'
        option ula_prefix 'fdad:6575:cb32::/48'

config device
        option name 'br-lan'
        option type 'bridge'
        list ports 'eth0'

config interface 'lan'
        option device 'br-lan'
        option proto 'dhcp'

config interface 'wan'
        option device 'eth1'
        option proto 'dhcp'


EOF

}


rip_config() {
    # $1 path where to save config file

    cat <<EOF > "$1"
service integrated-vtysh-config

router rip
 version 2
 network 10.0.0.0/8
 redistribute connected
log syslog
access-list vty permit 127.0.0.0/8
access-list vty deny any
line vty
 access-class vty
EOF
}

configure_openwrt() {

    echo -e "\033[1;33m [$0] Iniciant configuració openwrt ... \033[0m"

    "$vbox" startvm $openwrt_vmname
    echo "Waiting for $openwrt_vmname to boot..."
    sleep 20s

    ssh-keygen -R "[$ip_vm]:2222"
    ssh-keygen -R '[127.0.0.1]:2222'
    ssh-keygen -R '[localhost]:2222'

    ssh -p 2222 -o StrictHostKeyChecking=no -i "$idkeys_path" root@$ip_vm "
        opkg update
        opkg install frr frr-zebra frr-watchfrr frr-staticd frr-ripd openssl-util tcpdump
        sed -i 's/set timeout=.*/set timeout=\"0\"/' /boot/grub/grub.cfg
        sed -i 's/ripd=no/ripd=yes/' /etc/frr/daemons
        /etc/init.d/firewall disable
        /etc/init.d/frr enable
        "

    tmp_folder=$(mktemp -d)
    rip_file=$tmp_folder/frr.conf
    rip_config "$rip_file"
    scp -P 2222 $old_protocol -o StrictHostKeyChecking=no -i "$idkeys_path" "$rip_file" root@$ip_vm:/etc/frr/frr.conf


    "$vbox" controlvm "$openwrt_vmname" acpipowerbutton
    sleep 10s
    "$vbox" snapshot "$openwrt_vmname" take "base"

    echo -e "\033[1;33m [$0] Configuració openwrt finalitzada. \033[0m"

}

create_openwrtvm() {
    echo -e "\033[1;33m [$0] Iniciant creació openwrt ... \033[0m"

    "$vbox" createvm --name "$openwrt_vmname" --register --ostype "Linux_64" --groups "/$vcorp_group/templates"
    "$vbox" modifyvm "$openwrt_vmname" --memory 128
    "$vbox" storagectl "$openwrt_vmname" --name "SATA Controller" --add sata --controller IntelAhci --portcount 2
    "$vbox" storageattach "$openwrt_vmname" --storagectl "SATA Controller" --port 0 --device 0 --type hdd --medium "$vdi_path"
    "$vbox" modifyvm "$openwrt_vmname" --nic1 nat --natpf1 "ssh,tcp,,2222,,22"
    "$vbox" modifyvm "$openwrt_vmname" --nic2 intnet --nic3 intnet --nic4 intnet --nic5 intnet --nic6 intnet
    "$vbox" modifyvm "$openwrt_vmname" --natdnshostresolver1 on

    echo -e "\033[1;33m [$0] Creació openwrt finalitzada. \033[0m"
}

create_preseed() {
    # $1 path to save preseed.cfg
    # $2 hostname
    # $3 partition scheme: home (for desktop), multi (for servers), atomic (no partition, for user)
    # $4 list of packages to install ( standard,ssh-server,xfce,...)


    cat <<EOF >"$1/preseed.cfg"
#_preseed_V1
#### Contents of the preconfiguration file (for bookworm)
### Localization
# Preseeding only locale sets language, country and locale.
d-i debian-installer/locale string en_US

# Keyboard selection.
d-i keyboard-configuration/xkb-keymap select es
# d-i keyboard-configuration/toggle select No toggling

### Network configuration
# netcfg will choose an interface that has link if possible. This makes it
# skip displaying a list if there is more than one interface.
d-i netcfg/choose_interface select auto
#d-i netcfg/get_nameservers string 1.1.1.1
#d-i netcfg/confirm_static boolean true

# Any hostname and domain names assigned from dhcp take precedence over
# values set here. However, setting the values still prevents the questions
# from being shown, even if values come from dhcp.
d-i netcfg/get_hostname string $2
d-i netcfg/get_domain string lan

# Disable that annoying WEP key dialog.
d-i netcfg/wireless_wep string

### Mirror settings
# Mirror protocol:
# If you select ftp, the mirror/country string does not need to be set.
# Default value for the mirror protocol: http.
#d-i mirror/protocol string ftp
d-i mirror/country string manual
d-i mirror/http/hostname string http.us.debian.org
d-i mirror/http/directory string /debian
d-i mirror/http/proxy string

# Suite to install.
#d-i mirror/suite string testing
# Suite to use for loading installer components (optional).
#d-i mirror/udeb/suite string testing

### Account setup
# Skip creation of a root account (normal user account will be able to
# use sudo).
d-i passwd/root-login boolean false
# Alternatively, to skip creation of a normal user account.
#d-i passwd/make-user boolean false

# Root password, either in clear text
#d-i passwd/root-password password r00tme
#d-i passwd/root-password-again password r00tme
# or encrypted using a crypt(3)  hash.
#d-i passwd/root-password-crypted password [crypt(3) hash]

# To create a normal user account.
d-i passwd/user-fullname string SystemAdministrator
d-i passwd/username string $sysadmin_user
# Normal user's password, either in clear text
d-i passwd/user-password password Asdqwe!23
d-i passwd/user-password-again password Asdqwe!23

### Clock and time zone setup
# Controls whether or not the hardware clock is set to UTC.
d-i clock-setup/utc boolean true

# You may set this to any valid setting for $TZ; see the contents of
# /usr/share/zoneinfo/ for valid values.
d-i time/zone string Europe/Madrid

# Controls whether to use NTP to set the clock during the install
d-i clock-setup/ntp boolean true
# NTP server to use. The default is almost always fine here.
#d-i clock-setup/ntp-server string ntp.example.com

### Partitioning
## Partitioning example
# If the system has free space you can choose to only partition that space.
# This is only honoured if partman-auto/method (below) is not set.
#d-i partman-auto/init_automatically_partition select biggest_free

# Alternatively, you may specify a disk to partition. If the system has only
# one disk the installer will default to using that, but otherwise the device
# name must be given in traditional, non-devfs format (so e.g. /dev/sda
# and not e.g. /dev/discs/disc0/disc).
# For example, to use the first SCSI/SATA hard disk:
#d-i partman-auto/disk string /dev/sda
# In addition, you'll need to specify the method to use.
# The presently available methods are:
# - regular: use the usual partition types for your architecture
# - lvm:     use LVM to partition the disk
# - crypto:  use LVM within an encrypted partition
d-i partman-auto/method string regular


# You can choose one of the three predefined partitioning recipes:
# - atomic: all files in one partition
# - home:   separate /home partition
# - multi:  separate /home, /var, and /tmp partitions
d-i partman-auto/choose_recipe select $3


# This makes partman automatically partition without confirmation, provided
# that you told it what to do using one of the methods above.
d-i partman-partitioning/confirm_write_new_label boolean true
d-i partman/choose_partition select finish
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true

### Apt setup
# Choose, if you want to scan additional installation media
# (default: false).
d-i apt-setup/cdrom/set-first boolean false
# You can choose to install non-free firmware.
#d-i apt-setup/non-free-firmware boolean true
# You can choose to install non-free and contrib software.
#d-i apt-setup/non-free boolean true
#d-i apt-setup/contrib boolean true
# Uncomment the following line, if you don't want to have the sources.list
# entry for a DVD/BD installation image active in the installed system
# (entries for netinst or CD images will be disabled anyway, regardless of
# this setting).
#d-i apt-setup/disable-cdrom-entries boolean true
# Uncomment this if you don't want to use a network mirror.
#d-i apt-setup/use_mirror boolean false
# Select which update services to use; define the mirrors to be used.
# Values shown below are the normal defaults.
#d-i apt-setup/services-select multiselect security, updates
#d-i apt-setup/security_host string security.debian.org

### Package selection
tasksel tasksel/first multiselect $4uname

# Copiar authorized_keys des del medi d'instal·lació (/cdrom) cap al sistema instal·lat (/target)
d-i preseed/late_command string \
    ( mkdir -p /target/home/$sysadmin_user/.ssh; \
    cp /cdrom/authorized_keys /target/home/$sysadmin_user/.ssh/authorized_keys; \
    in-target chown -R $sysadmin_user:$sysadmin_user /home/$sysadmin_user/.ssh; \
    in-target chmod 700 /home/$sysadmin_user/.ssh; \
    in-target chmod 600 /home/$sysadmin_user/.ssh/authorized_keys; \
    echo "$sysadmin_user ALL=(ALL) NOPASSWD:ALL" > /target/etc/sudoers.d/$sysadmin_user ) > /target/root/late_command.log 2>&1

# You can choose, if your system will report back on what software you have
# installed, and what software you use. The default is not to report back,
# but sending reports helps the project determine what software is most
# popular and should be included on the first CD/DVD.
popularity-contest popularity-contest/participate boolean false

### Boot loader installation
# Grub is the boot loader (for x86).

# This is fairly safe to set, it makes grub install automatically to the UEFI
# partition/boot record if no other operating system is detected on the machine.
d-i grub-installer/only_debian boolean true

# This one makes grub-installer install to the UEFI partition/boot record, if
# it also finds some other OS, which is less safe as it might not be able to
# boot that other OS.
d-i grub-installer/with_other_os boolean true

# Due notably to potential USB sticks, the location of the primary drive can
# not be determined safely in general, so this needs to be specified:
#d-i grub-installer/bootdev  string /dev/sda
# To install to the primary device (assuming it is not a USB stick):
d-i grub-installer/bootdev  string default

# Optional password for grub, either in clear text
#d-i grub-installer/password password r00tme
#d-i grub-installer/password-again password r00tme
# or encrypted using an MD5 hash, see grub-md5-crypt(8).
#d-i grub-installer/password-crypted password [MD5 hash]

# Avoid that last message about the install being complete.
d-i finish-install/reboot_in_progress note

# This is how to make the installer shutdown when finished, but not
# reboot into the installed system.
#d-i debian-installer/exit/halt boolean true
# This will power off the machine instead of just halting it.
d-i debian-installer/exit/poweroff boolean true

### Preseeding other packages
# Depending on what software you choose to install, or if things go wrong
# during the installation process, it's possible that other questions may
# be asked. You can preseed those too, of course. To get a list of every
# possible question that could be asked during an install, do an
# installation, and then run these commands:
#   debconf-get-selections --installer > file
#   debconf-get-selections >> file

EOF

}


deb_prepare_iso() {
    # $1 path to decompress debian iso
    echo "Checking Debian ISO in local filesystem..."
    existing_iso=$(find "$download_folder" -name "$debian_iso_filename" -maxdepth 1 2> /dev/null | head -1)
    iso_path=$(dirname $existing_iso 2> /dev/null)
    if [[ -n $iso_path ]]
    then
        download_folder=$iso_path
        echo "ISO found at: $download_folder/$debian_iso_filename"
    fi

    [[ -n $iso_path ]] || wget -P "$download_folder" "$debian_url"
    if [[ $(sha256sum "$download_folder/$debian_iso_filename" | cut -d' ' -f1) != "$debian_iso_checksum" ]]
    then
        echo "Bad Debian ISO..."
        exit 1
    fi
    [ -d "$download_folder/isolinux" ] || bsdtar -xf "$download_folder/$debian_iso_filename" -C "$download_folder"
}

deb_create_preseeded_iso() {
    # $1 tmp_folder path where original iso has been decompressed
    # $2 hostname
    # $3 partition scheme
    # $4 list of packages to install
    # $5 path to auth identity file (id_rsa.pub) of sysadmin user
    # $6 path where to save preseeded iso
    echo "Preparing ISO files for preseeding..."
    cp "$5" "$1/authorized_keys"
    create_preseed "$1" $2 $3 $4
    chmod -R +w "$1/isolinux"

    sed -i 's/---\s*quiet\s*$/locale=en_US keyboard-configuration\/xkb-keymap=es --- quiet file=\/cdrom\/preseed.cfg /' "$1/isolinux/txt.cfg"
    {
        echo "default install"
        echo "timeout 0"
        echo "prompt 0"
    } >>"$1/isolinux/isolinux.cfg"
    echo "Creating ISO..."
    mkisofs -v -o "$6" -b "isolinux/isolinux.bin" \
        -c "isolinux/boot.cat" -boot-info-table -no-emul-boot -boot-load-size 4 \
        -V "Debian ISO" -R -J "$1"
    echo "ISO created..."
}

deb_create_vm() {
    # $1 virtualbox machine name
    # $2 path to preseeded iso

    echo -e "\033[1;33m [$0] Iniciant creació debian server ... \033[0m"

    "$vbox" createvm --name "$1" --ostype "Debian_64" --register --groups "/$vcorp_group/templates"
    "$vbox" modifyvm "$1" --memory 1024 --cpus 1
    "$vbox" modifyvm "$1"  --nic1 nat --natpf1 "ssh,tcp,,2222,,22"
    "$vbox" createhd --filename "$wsl_vbox_templates_path/$1/$1.vdi" --size 50000
    "$vbox" storagectl "$1" --name "SATA Controller" --add sata --controller IntelAhci --portcount 2
    "$vbox" storageattach "$1" --storagectl "SATA Controller" --port 0 --device 0 --type hdd --medium "$wsl_vbox_templates_path/$1/$1.vdi"
    "$vbox" storagectl "$1" --name "IDE Controller" --add ide
    "$vbox" storageattach "$1" --storagectl "IDE Controller" --port 0 --device 0 --type dvddrive --medium "$2"
    "$vbox" modifyvm "$1" --natdnshostresolver1 on

    "$vbox" startvm "$1"

    echo -e "\033[1;33m [$0] Esperant que la instal·lació de Debian acabi (la màquina s'apagarà automàticament)...\033[0m"

    # Timeout de seguretat (15 minuts)
    start_time=$(date +%s)
    timeout=900

    # Bucle d’espera
    while true; do
        state=$("$vbox" showvminfo "$1" --machinereadable | grep -i '^VMState=' | cut -d'=' -f2 | tr -d '"')
        if [ "$state" = "poweroff" ]; then
            echo "Instal·lació completada: la màquina '$1' s'ha apagat."
            break
        fi

        now=$(date +%s)
        if (( now - start_time > timeout )); then
            echo " Temps d'espera esgotat. La instal·lació pot haver fallat."
            exit 1
        fi

        sleep 10
    done

    # Desmuntar automàticament el CD-ROM (ISO)
    echo "Desmuntant la imatge ISO..."
    "$vbox" storageattach "$1" --storagectl "IDE Controller" --port 0 --device 0 --medium none

    echo -e "\033[1;33m [$0] Creació debian server finalitzat. \033[0m"

}

configure_debian_server() {

    echo -e "\033[1;33m [$0] Iniciant configuració debian server ... \033[0m"

    debian_vmname=debian_server_template

    "$vbox" startvm "$debian_vmname"
    echo "Waiting for $debian_vmname to boot..."
    sleep 20s

    ssh-keygen -R "[$ip_vm]:2222"
    ssh-keygen -R '[127.0.0.1]:2222'
    ssh-keygen -R '[localhost]:2222'

    ssh -tt -p 2222 -o StrictHostKeyChecking=no -i "$idkeys_path" $sysadmin_user@$ip_vm <<EOF
        sudo apt-get update && sudo apt-get upgrade -y
        sudo sed -i 's/GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' /etc/default/grub
        sudo update-grubº
EOF

    "$vbox" controlvm "$debian_vmname" acpipowerbutton
    sleep 10s
    "$vbox" snapshot "$debian_vmname" take "base"

    echo -e "\033[1;33m [$0] Configuració debian server finalitzada. \033[0m"

}

create_debian_desktop() {
    # $1 debian_server_template (we'll clone this to create desktop)

    echo -e "\033[1;33m [$0] Iniciant creació debian desktop ... \033[0m"

    debian_vmname=debian_desktop_template

    "$vbox" clonevm "$1" --groups "/$vcorp_group/templates" --name "$debian_vmname" --register --snapshot base --options=Link
    "$vbox" modifyvm "$debian_vmname" --groups "/$vcorp_group/templates" 
    "$vbox" modifyvm "$debian_vmname" --natdnshostresolver1 on

    "$vbox" startvm "$debian_vmname"
    echo "Waiting for $debian_vmname to boot..."
    sleep 20s

    ssh-keygen -R "[$ip_vm]:2222"
    ssh-keygen -R '[127.0.0.1]:2222'
    ssh-keygen -R '[localhost]:2222'

    ssh -p 2222 -o StrictHostKeyChecking=no -i "$idkeys_path" $sysadmin_user@$ip_vm "
        sudo apt-get install -y lxde-core lxde-common lxterminal lxappearance
        "

    "$vbox" controlvm "$debian_vmname" acpipowerbutton
    sleep 10s
    "$vbox" snapshot "$debian_vmname" take "base"

    echo -e "\033[1;33m [$0] Creació debian desktop finalitzada. \033[0m"

}


show_help() {
    cat <<EOF
Usage: $0 [OPTION]...

Opcions:
  -r, --create-router     Crea la màquina virtual del router OpenWRT
  -s, --create-server     Crea la màquina virtual del servidor Debian
  -d, --create-desktop    Crea la màquina virtual d'escriptori Debian
  -h, --help              Mostra aquest missatge d'ajuda
  -i, --iso               Indica una carpeta local donde se encuentran las ISOs descargadas, sino se encuentra la ISO en la ruta por default, 
                          se le pedirá que pase la ruta donde se encuentra la ISO

Aquest script permet crear plantilles de màquines virtuals per a diverses configuracions:
  1. Router amb OpenWRT
  2. Servidor amb Debian (utilitzant preseed)
  3. Escriptori amb Debian (utilitzant preseed)

Exemples d'ús:
  $0 -r          Crea la màquina virtual del router OpenWRT
  $0 -s          Crea la màquina virtual del servidor Debian
  $0 -d          Crea la màquina virtual d'escriptori Debian
  $0 -rs         Crea tant la màquina del router com la del servidor

EOF
}


install_dependencies() {
    if which apt &> /dev/null; then
        sudo dpkg -l libarchive-tools mkisofs sshpass &> /dev/null
        if [ ! $? ]
        then
            sudo apt-get install -y libarchive-tools mkisofs sshpass
        fi
    elif which pacman &> /dev/null; then
        sudo pacman -Q | grep "libarchive\|cdrtools\|sshpass" &> /dev/null
        if [ $? ]
        then
            sudo pacman -Syu --noconfirm --needed libarchive cdrtools sshpass
        fi
    else
        echo "Cal instal·lar libarchive-tools (o bsdtar en algunes distribucions) i mkisofs"
        echo ""
    fi
}


if [ "$1" = "" ]; then
    eval set -- "-rsd"
fi

args=$(getopt -o rsdhi:R:D: \
    --long create-router,create-server,help,create-desktop,iso:,debian-url:,openwrt-url: --name "$0" -- "$@")

eval set -- "${args}"

while true; do
  case "$1" in
    -h|--help)           
    opc_help=1; shift ;;
    -r|--create-router)  
    opc_create_router=1; shift ;;
    -s|--create-server)  
    opc_create_server=1; shift ;;
    -d|--create-desktop) 
    opc_create_desktop=1; shift ;;
    -i|--iso)
    iso_dir="$2"; shift 2 ;;
    --debian-url)
    debian_url="$2"; shift 2 ;;
    --openwrt-url)       
    openwrt_url="$2"; shift 2 ;;
    --) shift; break ;;
    *) break ;;
  esac
done

test -z $opc_help && check_platform

mkdir -p "$default_vm_location"
"$vbox" setproperty machinefolder "$wsl_default_vm_location"

if [[ -n $iso_dir ]]; then
    custom_iso_dir
else
    if ! (( is_wsl )); then
        download_folder=$(mktemp -d)
    fi
fi

[[ -n $opc_help ]] && show_help

[[ -n $opc_create_router ]] && {
    install_dependencies
    echo "** Deleting $openwrt_vmname **"
    "$vbox" unregistervm "$openwrt_vmname" --delete 2>/dev/null 

    echo ""
    echo "** Creating $openwrt_vmname **"
    create_openwrtvdi
    create_openwrtvm
    configure_openwrt
}

# Comprovar si existeixen les variables opc_create_desktop o opc_create_server
if [[ -n $opc_create_desktop || -n $opc_create_server ]]; then
    install_dependencies
    # Executar prepare_iso sempre
    deb_prepare_iso
    tmp_folder=$download_folder
    echo "Debian ISO found in: $tmp_folder"

    # Si existeix opc_create_server, executa create_server
    if [[ -n $opc_create_server ]]; then
        echo ""
        echo "** Deleting $srv_template_vmname **"
        "$vbox" unregistervm "$srv_template_vmname" --delete
        echo ""
        "$vbox" list vms

        [ -f "$download_folder/debian_server_template.iso" ] || deb_create_preseeded_iso "$tmp_folder" deb-srv-template multi standard,ssh-server,tcpdump "$idkeys_path.pub" "$download_folder/debian_server_template.iso"
        deb_create_vm $srv_template_vmname "$download_folder/debian_server_template.iso"
        echo "Waiting for $srv_template_vmname to shutdown..."
        sleep 10s
        configure_debian_server
    fi

    # Si existeix opc_create_desktop, executa create_desktop
    if [[ -n $opc_create_desktop ]]; then
        echo "** Deleting $desktop_template_vmname **"
        "$vbox" unregistervm "$desktop_template_vmname" --delete 2>/dev/null

        echo ""
        create_debian_desktop debian_server_template
    fi

fi
