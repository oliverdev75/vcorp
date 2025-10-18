#!/bin/bash

ovaFile=VirtualLab.ova
baseGroupName="/VCorp"

router_template=openwrt_template
server_template=debian_server_template
basic_client_template=debian_desktop_template

if grep -q microsoft /proc/version; then
    # Estem en entorn WSL
    echo "Configurant per entorn WSL"
    vbox="/mnt/c/Program Files/Oracle/VirtualBox/VBoxManage.exe"
    default_vm_location="/mnt/c/VirtualCorp"
    wsl_default_vm_location="C:\\VirtualCorp"

else
    # Estem en entorn Linux natiu
    echo "Configurant per entorn Linux natiu"
    vbox="vboxmanage"
    default_vm_location="$HOME/VirtualBox VMs"
    wsl_default_vm_location="$HOME/VirtualBox VMs"
fi



# Definició de les xarxes
# [network_name]=cidr
declare -A networks=(
    ["VCorp_DMZ"]="10.0.0.192/27"
    ["VCorp_private"]="10.0.0.128/26"
    ["VCorp_pl0"]="10.0.0.0/25"
    ["VCorp_pl1"]="10.0.1.0/24"
    ["VCorp_pl2"]="10.0.2.0/24"
    ["VCorp_pl3"]="10.0.3.0/25"
    ["VCorp_direccion"]="10.0.3.128/25"
    ["VCorp_rt0_1"]="10.0.0.224/30"
    ["VCorp_rt1_2"]="10.0.0.228/30"
    ["VCorp_rt2_3"]="10.0.0.232/30"

)


# [server_name] group_name template_name network_name count
declare -A servers=(
    ["websrv"]="DMZ debian_server_template VCorp_DMZ 1"
    ["streamingsrv"]="DMZ debian_server_template VCorp_DMZ 1"
    ["intrasrv"]="Private debian_server_template VCorp_private 1"
    ["coresrv"]="Private debian_server_template VCorp_private 1"
    ["datasrv"]="Private debian_server_template VCorp_private 1"
    ["infosrv"]="Private debian_server_template VCorp_private 1"
    ["conserge"]="planta00 debian_desktop_template VCorp_pl0 2"
    ["expo"]="planta00 debian_desktop_template VCorp_pl0 4"
    ["pl1-pc"]="planta01 debian_desktop_template VCorp_pl1 3"
    ["pl2-pc"]="planta02 debian_desktop_template VCorp_pl2 3"
    ["pl3-pc"]="planta03 debian_desktop_template VCorp_pl3 3"
    ["pl1-printer"]="planta01 debian_desktop_template VCorp_pl1 1"
    ["pl2-printer"]="planta02 debian_desktop_template VCorp_pl2 1"
    ["pl3-printer"]="planta03 debian_desktop_template VCorp_pl3 1"
)



create_server() {
    # $1=server_name $2=group_name $3=template_name $4=network_name $5=count
    for i in $(seq 1 "$5"); do
        srvname="$1"
        [[ $5 -gt 1 ]] && srvname="$(printf "%s%02d" "$1" "$i")"
        "$vbox" clonevm "$3" --groups "$baseGroupName/$2" --name "$srvname" --register --snapshot base --options=Link
        "$vbox" modifyvm "$srvname" --groups "$baseGroupName/$2" --nic1 intnet --intnet1 "$4"
    done
}

create_servers_of_group() {
    # $1=group_name

    for srv in "${!servers[@]}"; do
        echo "$srv ${servers[$srv]}" | { read -r srv_name srv_group srv_template srv_net srv_count
            [[ $srv_group = "$1" ]] && create_server "$srv_name" "$srv_group" "$srv_template" "$srv_net" "$srv_count"
        }
    done
}


get_all_vms_uuid() {
    "$vbox" list vms | sed 's/.*{\(.*\)}/\1/'
}

get_vms_group() {
    "$vbox" list vms -l | \
        grep -E "^Groups:|^Name:" | sed -E "s/.*:\s+//" | \
        while read -r vmname ; do 
            read -r vmgroup  
            echo "$vmname $vmgroup" 
        done
}

get_vms_of_group() {
    get_all_vms_uuid | while read -r uuid ; do 
        # Evitar problemes amb el CR de Windows
        uuid=$(echo "$uuid" | sed 's/\r//g')
        "$vbox" showvminfo "$uuid" | grep -E "^Groups:\s+$1" >/dev/null && echo "$uuid"
    done
}

rm_vms_of_group() {
    get_vms_of_group "$1" | while read -r uuid ; do
        echo "$uuid"
        "$vbox" unregistervm "$uuid" --delete-all >/dev/null
    done
}

rm_all_groups() {
    for group_name in "${groups[@]}" ; do
        rm_vms_of_group "$baseGroupName/$group_name"
    done
}

list_vms_names() {
    get_vms_group | while read -r vmname vmgroup ; do
        if [[ $vmgroup =~ ^${baseGroupName}[a-zA-Z0-9_/]*$ ]] ; then
            echo "$vmname"
        fi
    done
}



import_ova() {
"$vbox" import "$ovaFile" \
    --vsys=0 --vmname "${server_template}" --group "$baseGroupName/templates" \
    --vsys=1 --vmname "${router_template}" --group "$baseGroupName/templates" \
    --vsys=2 --vmname "${basic_client_template}" --group "$baseGroupName/templates"
echo "VMx imported. Taking snapshots..."
"$vbox" snapshot "${router_template}" take "base" 
"$vbox" snapshot "${server_template}" take "base" 
"$vbox" snapshot "${basic_client_template}" take "base" 
echo "Taking snapshots done."
}


create_routers() {
    "$vbox" clonevm "$router_template" --groups "$baseGroupName/routers" --name router0 --register --snapshot base
    "$vbox" clonevm "$router_template" --groups "$baseGroupName/routers" --name router1 --register --snapshot base
    "$vbox" clonevm "$router_template" --groups "$baseGroupName/routers" --name router2 --register --snapshot base
    "$vbox" clonevm "$router_template" --groups "$baseGroupName/routers" --name router3 --register --snapshot base
    # Modify group assignment as --groups option in clonevm is not working
    "$vbox" modifyvm router0 --groups "$baseGroupName/routers"
    "$vbox" modifyvm router1 --groups "$baseGroupName/routers"
    "$vbox" modifyvm router2 --groups "$baseGroupName/routers"
    "$vbox" modifyvm router3 --groups "$baseGroupName/routers"

    # Configuració interficies xarxa router 0
    # tarja 1 (nic1) -> connectada a wan, tarja2 -> dmz, tarja3-> router1
    "$vbox" modifyvm router0 --nic1 nat --nic2 intnet --intnet2 VCorp_DMZ --nic3 intnet --intnet3 VCorp_rt0_1

    "$vbox" modifyvm router1 --nic1 intnet --intnet1 VCorp_rt0_1 --nic2 intnet --intnet2 VCorp_private --nic3 intnet --intnet3 VCorp_rt1_2
    "$vbox" modifyvm router2 --nic1 intnet --intnet1 VCorp_rt1_2 --nic2 intnet --intnet2 VCorp_pl0 --nic3 intnet --intnet3 VCorp_pl1 --nic4 intnet --intnet4 VCorp_rt2_3
    "$vbox" modifyvm router3 --nic1 intnet --intnet1 VCorp_rt2_3 --nic2 intnet --intnet2 VCorp_pl2 --nic3 intnet --intnet3 VCorp_pl3 --nic4 intnet --intnet4 VCorp_direccion
}



create_dev_servers() {
    # project_name group nat_network
    wwwSrvName="$1_www"
    "$vbox" clonevm "$server_template" --groups "$baseGroupName/$2" --name "$wwwSrvName" --register --snapshot base --options=Link
    "$vbox" modifyvm "$wwwSrvName" --groups "$baseGroupName/$2" --nic1 intnet --intnet1 "$3"

    dataSrvName="$1_data"
    "$vbox" clonevm "$server_template" --groups "$baseGroupName/$2" --name "$dataSrvName" --register --snapshot base --options=Link
    "$vbox" modifyvm "$dataSrvName" --groups "$baseGroupName/$2" --nic1 intnet --intnet1 "$3"
}


show_help() {
    cat <<EOF
Ús: $0 [opcions]

Aquest script automatitza la creació i gestió de l'entorn de laboratori virtual "VCorp" 
a VirtualBox, utilitzant màquines virtuals basades en plantilles importades des d'un fitxer OVA.

Opcions disponibles:
    -i, --import-ova
        Importa el fitxer $ovaFile a VirtualBox. 
        Aquest fitxer ha de contenir tres màquines:
          - $router_template
          - $server_template
          - $basic_client_template
        que s'utilitzaran com a plantilles per crear les VM del laboratori.

    -r, --create-routers
        Crea els routers principals (router0–router3) amb la seva configuració de xarxes.

    -a, --create-all-servers
        Crea totes les màquines de servidor i clients de VCorp, excepte els routers.

    -g, --create-group <nom-grup>
        Crea totes les màquines corresponents a un grup concret.
        Grups definits: ${groups[*]}

    -d, --create-dev-servers
        Crea servidors web i de dades per a tres projectes de desenvolupament (prj1–prj3)
        als grups especificats.

    --rm-group <nom-grup>
        Elimina totes les màquines virtuals que pertanyen al grup indicat.

    --rm-all-groups
        Elimina totes les màquines virtuals de tots els grups definits.

    --list
        Mostra els noms de totes les màquines virtuals actualment creades a l'entorn VCorp.

    -h, --help
        Mostra aquesta ajuda i surt.

Notes:
  - L’script detecta automàticament si s’executa en un entorn WSL o Linux natiu.
  - Les màquines s’organitzen dins del grup base: $baseGroupName
  - Si s’executa sense opcions, és equivalent a executar: 
        $0 -ra
EOF
}




if [ "$1" = "" ] ; then
    eval set -- "-r"
fi

args=$(getopt -o irg:d \
    --long ,help,import-ova,\
create-routers,create-group:,\
create-dev-servers,rm-all-groups,rm-group:,\
list \
    --name "$0"  -- "$@")

eval set -- "${args}"


while true ; do
    case "${1}" in
        -h | --help )
            opc_help=
        shift
        ;;
        -i | --import-ova )
            opc_import_ova=
            shift;;
        -r | --create-routers)
            opc_create_routers=
            shift;;
        --create-group)
            opc_create_group=
            create_group_name=$2
            shift 2 ;;
        -d | --create-dev-servers)
            opc_create_dev=
            shift;;
        --rm-group)
            opc_rm_group=
            rm_group_name="$2"
            shift 2 ;;
        --rm-all-groups)
            opc_rm_all_groups=
            shift ;;
        --list)
            opc_list=
            shift ;;
        --)
            shift;
            break
        ;;
    esac
done

"$vbox" setproperty machinefolder "$wsl_default_vm_location"

test -v opc_help && show_help

test -v opc_rm_group && rm_vms_of_group "$rm_group_name" 
test -v opc_rm_all_groups && rm_all_groups

test -v opc_import_ova && { 
    import_ova || exit 128 
    }

test -v opc_create_routers && create_routers
test -v opc_create_group && create_servers_of_group "$create_group_name"
test -v opc_create_dev && {
    create_dev_servers prj1 planta01 VCorp_pl1
    create_dev_servers prj2 planta01 VCorp_pl1
    create_dev_servers prj3 planta02 VCorp_pl2
}
test -v opc_list && list_vms_names
