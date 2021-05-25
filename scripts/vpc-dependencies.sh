#!/bin/bash
# see https://aws.amazon.com/premiumsupport/knowledge-center/troubleshoot-dependency-error-delete-vpc/

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <vpc_id> <--yes>"
    exit 1
fi

ec2="aws ec2"
vpc_id="$1"
allyes="$2"

function clean_quots {
    echo "$1" | sed -r 's/[",]+//g'
}

function extract {
    local cmd=$1
    local id_type=$2
    local segment=$($ec2 $cmd | grep $id_type | sed -e 's/^[[:space:]]*//')

    if [ ! -z "$segment" ]; then
        arr=(${segment//:/ })

        local _key=$(clean_quots ${arr[0]})
        local _val=$(clean_quots ${arr[1]})

        echo "=> found $_key $_val"

        if [ "$allyes" = "--yes" ]; then
            _yes="yes"
        else
            echo "Do you want to delete this resource? Only 'yes' will be accepted to confirm."
            read _yes
        fi

        # see https://docs.aws.amazon.com/cli/latest/reference/ec2/
        # see https://docs.aws.amazon.com/cli/latest/reference/elb/
        if [ "$_yes" = "yes" ]; then
            case $_key in
            "InternetGatewayId")
                $ec2 delete-internet-gateway --internet-gateway-id $_val
                ;;
            "SubnetId")
                $ec2 delete-subnet --subnet-id $_val
                ;;
            "RouteTableId")
                $ec2 delete-route-table --route-table-id $_val
                ;;
            "NetworkAclId")
                $ec2 delete-network-acl --network-acl-id $_val
                ;;
            "VpcPeeringConnectionId")
                $ec2 delete-vpc-peering-connection --vpc-peering-connection-id $_val
                ;;
            "VpcEndpointId")
                $ec2 delete-vpc-endpoints --vpc-endpoint-ids $_val
                ;;
            "NatGatewayId")
                $ec2 delete-nat-gateway --nat-gateway-id $_val
                ;;
            "GroupId")
                $ec2 delete-security-group --group-name $_val
                ;;
            "InstanceId")
                $ec2 terminate-instances --instance-ids $_val
                ;;
            "VpnConnectionId")
                $ec2 delete-vpn-connection --vpn-connection-id $_val
                ;;
            "VpnGatewayId")
                $ec2 delete-vpn-gateway --vpn-gateway-id $_val
                ;;
            "NetworkInterfaceId")
                $ec2 delete-network-interface --network-interface-id $_val
                ;;
            esac

            echo ""
        fi
    fi
}

extract "describe-internet-gateways --filters Name=attachment.vpc-id,Values=$vpc_id" "InternetGatewayId"
extract "describe-subnets --filters Name=vpc-id,Values=$vpc_id" "SubnetId"
extract "describe-route-tables --filters Name=vpc-id,Values=$vpc_id" "RouteTableId"
extract "describe-network-acls --filters Name=vpc-id,Values=$vpc_id" "NetworkAclId"
extract "describe-vpc-peering-connections --filters Name=requester-vpc-info.vpc-id,Values=$vpc_id" "VpcPeeringConnectionId"
extract "describe-vpc-endpoints --filters Name=vpc-id,Values=$vpc_id" "VpcEndpointId"
extract "describe-nat-gateways --filter Name=vpc-id,Values=$vpc_id" "NatGatewayId"
extract "describe-security-groups --filters Name=vpc-id,Values=$vpc_id" "GroupId"
extract "describe-instances --filters Name=vpc-id,Values=$vpc_id" "InstanceId"
extract "describe-vpn-connections --filters Name=vpc-id,Values=$vpc_id" "VpnConnectionId"
extract "describe-vpn-gateways --filters Name=attachment.vpc-id,Values=$vpc_id" "VpnGatewayId"
extract "describe-network-interfaces --filters Name=vpc-id,Values=$vpc_id" "NetworkInterfaceId"
