function
    local str0 = ...
    if #str0 > 0 then
        if string.sub(str0:toHex(), 1, 4) == "FEFE" then
            local ss = string.gsub(str0:toHex(), "FE", "")
            local kk0 = string.sub(ss, 5, 18) 
            local tmps0 = ""
            local tmplen0 = #kk0 / 2
            for i = tmplen0, 1, -1 do
                tmps0 = tmps0 .. string.sub(kk0, 2 * i - 1, 2 * i)
            end
            local meterno = tmps0
            local k1 = string.sub(ss, 29, 36)
            local tmps1 = ""
            local tmplen1 = #k1 / 2
            for i = tmplen1, 1, -1 do
                tmps1 = tmps1 .. string.sub(k1, 2 * i - 1, 2 * i)
            end
            local sn = misc.getImei()
            local tmps2 = string.gsub(tmps1, "^%z+", "")
            local tmps3 = tonumber(tmps2) * 10
            local meter_data = {
                DEVTYPE = "M3",
                GATEWAY = 1,
                SN = sn,
                METERNO = meterno,
                UPDATA = tmps3,
                FUNCCODE ="A2",
                PAYMODE = 1
            }
            str = json.encode(meter_data)
            return str, 1
        else
            return str0
        end
    end
end