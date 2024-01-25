#!/bin/bash

# Proxmox Setup v1.0.0
# by: Matheew Alves

# Carregar as variáveis de cores do arquivo colors.conf
cd /Proxmox-Debian12
source ./configs/colors.conf

# Tornando-se root
if [ "$(whoami)" != "root" ]; then
    echo -e "${ciano}Tornando-se superusuário...${normal}"
    sudo -E bash "$0" "$@"  # Executa o script como root
    exit $?
fi

# Caminho para o arquivo de configuração
config_file="configs/network.conf"

configure_bridge()
{
    # Verificar se o arquivo de configuração existe
    if [ ! -f "$config_file" ]; then
        echo -e "${amarelo}O arquivo de configuração ${ciano}$config_file${amarelo} não existe. Execute o script ${ciano}install_proxmox-1.sh${amarelo} primeiro ou configure manualmente.${normal}"
    fi

    # Ler as configurações do arquivo
    source "$config_file"

    # Exibindo informações de rede
    echo -e "${ciano}Exibindo interface de network.conf:${normal}"
    echo -e "${azul}Interface Física:${normal} $INTERFACE"
    echo -e "${azul}Endereço IP:${normal} $IP_ADDRESS"
    echo -e "${azul}Gateway:${normal} $GATEWAY ${normal}"

    # Utilizar as variáveis lidas do arquivo ou solicitar novas se estiverem em branco
    echo -e "${azul}Revisando configurações e as informações de interface de rede para criação da bridge...${normal}"
    PS3="Selecione uma opção (Digite o número): "
    options=("Configurar Manualmente" "Usar DHCP" "Sair")

    select opt in "${options[@]}"; do
        case $opt in
            "Configurar Manualmente")
                # Leitura manual das configurações
                read -p "Informe o nome da interface física / netmask (deixe em branco para manter "$INTERFACE"): " interface_fisica
                read -p "Informe o endereço IP para a bridge com net mask (deixe em branco para manter "$IP_ADDRESS"): " endereco_ip
                read -p "Informe o gateway para a bridge (deixe em branco para manter "$GATEWAY"): " gateway

                # Utilizar as variáveis lidas ou as novas informadas
                INTERFACE=${interface_fisica:-$INTERFACE}
                IP_ADDRESS=${endereco_ip:-$IP_ADDRESS}

                # Validar se o gateway é um endereço IP válido
                if [[ -n "$gateway" && ! "$gateway" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                    echo -e "${vermelho}Gateway inválido. Saindo...${normal}"
                    exit 1
                fi

                GATEWAY=${gateway:-$GATEWAY}

                # Atualizar o arquivo de configuração
                echo "INTERFACE=$INTERFACE" > "$config_file"
                echo "IP_ADDRESS=$IP_ADDRESS" >> "$config_file"
                echo "GATEWAY=$GATEWAY" >> "$config_file"

                # Comentar as configurações da interface física no arquivo de configuração
                sed -i "/iface $INTERFACE inet static/,/iface/ s/^/#/" /etc/network/interfaces
                sed -i "/iface $INTERFACE inet dhcp/,/iface/ s/^/#/" /etc/network/interfaces

                # Criar a bridge vmbr0 com as novas informações
cat <<EOF >> /etc/network/interfaces

# Bridge Proxmox
auto vmbr0
iface vmbr0 inet static
    address $IP_ADDRESS
    gateway $GATEWAY
    bridge_ports $INTERFACE
    bridge_stp off
    bridge_fd 0
EOF

                break 2
                ;;

            "Usar DHCP")
                # Configuração para DHCP

                # Comentar as configurações da interface física no arquivo de configuração
                sed -i "/iface $INTERFACE inet static/,/iface/ s/^/#/" /etc/network/interfaces
                sed -i "/iface $INTERFACE inet dhcp/,/iface/ s/^/#/" /etc/network/interfaces

# Criar a bridge vmbr0 com as novas informações
cat <<EOF >> /etc/network/interfaces

# Bridge Proxmox
auto vmbr0
iface vmbr0 inet dhcp
    bridge_ports $INTERFACE
    bridge_stp off
    bridge_fd 0
EOF

                break 2
                ;;

            "Sair")
                remove_start-script
                echo -e "${amarelo}Você pode configurar a bridge vmbr0 posteriormente executando o script ${ciano}/Proxmox-Debian12/scripts/configure_bridge.sh${amarelo}"
                echo -e ", manualmente ou através da interface web do Proxmox. Consulte a documentação do Proxmox para mais informações.${normal}"
                echo -e "${vermelho}Saindo...${normal}"
                exit 0
                ;;

            *) echo -e "${amarelo}Opção inválida${normal}";;
        esac
    done

    # Reiniciar o serviço de rede para aplicar as alterações
    echo -e "${amarelo}Reiniciando o serviço de rede...${normal}"
    systemctl restart networking
    ip link set dev vmbr0 up

    echo -e "${verde}A bridge vmbr0 foi criada com sucesso!${normal}"
}

# Remover inicialização do script junto com o sistema
remove_start-script() 
{
    for user_home in /home/*; do
        PROFILE_FILE="$user_home/.bashrc"
        
        # Remover a linha do script do arquivo de perfil
        sed -i '/# Executar script após o login/,/# Fim do script 2/d' "$PROFILE_FILE"
        echo -e "${azul}Removida a configuração do perfil para o usuário:${ciano} $(basename "$user_home").${normal}"

       # Remover as linhas adicionadas ao /root/.bashrc
        sed -i '/# Executar script após o login/,/\/Proxmox-Debian12\/scripts\/configure_bridge.sh/d' /root/.bashrc
        echo -e "${azul}Removida a configuração automática do script no /root/.bashrc.${normal}"
    done
}

add_welcome()
{
    for user_home in /home/*; do
        PROFILE_FILE="$user_home/.bashrc"
        
        # Verifica se o arquivo de perfil existe antes de adicionar
        if [ -f "$PROFILE_FILE" ]; then
            # Adiciona a linha de execução do script ao final do arquivo
            echo "" >> "$PROFILE_FILE"
            echo "# Executar script após o login" >> "$PROFILE_FILE"
            echo "/Proxmox-Debian12/scripts/custom_welcome.sh" >> "$PROFILE_FILE"
            echo "" >> "$PROFILE_FILE"

            echo "Configuração automática concluída para o usuário: $(basename "$user_home")."
        fi

        # Adicione as seguintes linhas ao final do arquivo /root/.bashrc
        echo "" >> /root/.bashrc
        echo "# Executar script após o login" >> /root/.bashrc
        echo "/Proxmox-Debian12/scripts/custom_welcome.sh" >> /root/.bashrc
        echo "" >> /root/.bashrc

        echo "Configuração automática concluída para o usuário root."
    done
}

main()
{
    echo -e "${ciano}3º parte: Atualizando /etc/hosts..."
    echo -e "Passo 1/3"
    echo -e "...${normal}"
    configure_bridge
    remove_start-script
    add_welcome
    echo -e "${amarelo}(Opcional)${ciano}Deseja reiniciar o computador agora? [S/N]${normal}"
    read -p "Resposta: " perguntar_reboot

    perguntar_reboot=$(echo "$perguntar_reboot" | tr '[:upper:]' '[:lower:]')

    if [ "$perguntar_reboot" == "s" ]; then
        echo -e "${verde}Instalação e configuração de rede do Proxmox concluída com sucesso!${normal}"
        echo -e "${amarelo}Lembre-se de configurar o Proxmox conforme necessário.${normal}"
        echo -e "${amarelo}Reiniciando o Sistema...${normal}"
        sleep 5
        systemctl reboot
    fi

    echo -e "${verde}Instalação e configuração de rede do Proxmox concluída com sucesso!${normal}"
    echo -e "${amarelo}Lembre-se de configurar o Proxmox conforme necessário!${normal}"
    echo -e "${amarelo}Você pode configurar a bridge vmbr0 posteriormente executando o script ${ciano}/Proxmox-Debian12/scripts/configure_bridge.sh${amarelo}"
    echo -e ", manualmente ou através da interface web do Proxmox. Consulte a documentação do Proxmox para mais informações.${normal}"
    sleep 5
    clear

    ./custom_welcome
}

main
