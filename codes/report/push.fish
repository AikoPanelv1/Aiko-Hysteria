function push
    #def vars
    set users raw_statis
    # Create UserTable
    set users (yq '.users[].id' userlist)
    # Map id <=> uuid <=> base64_authstr
    for user in $users
        set uuid[$user] (yq ".users[]|select(.id == $user)|.uuid" userlist)
        set basestr[$user] (echo -n "$uuid[$user]" | base64)
    end
    # fetch data from api
    set raw_statis (curl -sL "http://127.0.0.1:$api_port/metrics" | string collect)
    if test -z $raw_statis
        if test "$bodhi_verbose" = debug
            logger 3 "@bodhi.push CONT -> No user, report empty"
        end
    else
        # Loop to collect data High-Passly
        for line_stat in (curl -sL "http://127.0.0.1:$api_port/metrics")
            if string match -q '*'\#'*' -- $line_stat; or string match -q '*active_conn*' -- $line_stat
            else
                set line_id (contains --index -- (string match -r 'auth="(.+?)"' $line_stat)[2] $basestr)
                if string match -rq uplink -- $line_stat
                    set upload[$line_id] (math (string split ' ' -- $line_stat)[2])
                else
                    set download[$line_id] (math (string split ' ' -- $line_stat)[2])
                end
            end
        end
        # compose json data
        set return_data '{}'
        for user in $users
            if test -z $upload[$user]; and test -z $download[$user]
            else
                set return_data (echo -n "$return_data" | yq -o=json ".$user = [$upload[$user], $download[$user]]")
            end
        end
        if test "$bodhi_verbose" = debug
            logger 3 "@bodhi.push CONT -> Ready to push with following data"
            logger 3 "
$return_data"
        end
        # Report data to panel
        set clength (echo -n "$return_data" | wc -c)
        curl -sL -X POST -H "Content-Type: application/json" -H "Content-Length: $clength" -d "$return_data" "$upstream_api/api/v1/server/UniProxy/push?node_id=$nodeid&node_type=hysteria&token=$psk" | yq
    end
end