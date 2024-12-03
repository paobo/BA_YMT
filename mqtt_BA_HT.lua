-- local mqtt_test = {}
-- _G.sys = require("sys")
--[[特别注意, 使用mqtt库需要下列语句]] -- _G.sysplus = require("sysplus")
local reason, slp_state = pm.lastReson()  --获取唤醒原因
log.info("wakeup state", reason)
adc.open(adc.CH_VBAT)
local mybat = adc.get(adc.CH_VBAT)
adc.close(adc.CH_VBAT)

if fskv.get("bauds") == nil then
    fskv.set("bauds", 9600) ------- 设置默认波特率
    fskv.set("uptime", 60) ------- 设置自动上传周期，默认60分钟【单位分钟】
    fskv.set("senttime",2355) --------设置自动上传的整点时间，2400为每个整点都上报，其余为指定时间上报
    fskv.set("rebootnum", 3)
end

local dev_data = nil
local meter_data = nil
local rebootnum = fskv.get("rebootnum")
local senttime = fskv.get("senttime")
local mqtt_host = "mqtt.yihuan100.com"
local mqtt_port = 1883
local mqtt_isssl = false
local client_id = "AIR780E-" .. mobile.imei(0)
local user_name = "ht1234"
local password = "ht1234"
local meterno = nil
local alldata = nil
local metersum = ""
local pub_topic = "hengtong/meter/s/" .. mobile.imei(0)
local sub_topic = "hengtong/meter/p/" .. mobile.imei(0)
---log.info("batt",mybat)
-- if mybat > 4000 then
--     pub_topic = "yomtey/test/s/" .. mobile.imei(0)
--     sub_topic = "yomtey/test/p/" .. mobile.imei(0)
-- end

local mqttc = nil
local bauds0 = nil
-- local bauds = nil
local bauds = fskv.get("bauds") --------获得波特率
--local uptime = fskv.get("uptime") --------获得自动上传周期
local uptime = nil --------获得自动上传周期
local device_id = mobile.imei(0)
local ccid = mobile.iccid(0)
local table_baud = {9600,4800,2400}
local i = 1
local wake_delay = 15000
if reason == 2 then
    wake_delay = 25000
end

sys.taskInit(function()
    gpio.setup(23, nil)
    gpio.close(12)
    gpio.close(13)

    -- gpio.close(33) --如果功耗偏高，开始尝试关闭WAKEUPPAD1
    --gpio.close(32) -- 如果功耗偏高，开始尝试关闭WAKEUPPAD0
    gpio.setup(32, function() end, gpio.PULLUP)
    gpio.close(35) -- 这里pwrkey接地才需要，不接地通过按键控制的不需要
    log.info("bauds", bauds)
    uart.setup(1, bauds, 8, 1, uart.EVEN)
    sys.wait(100)
    -- FE FE FE 68 10 AA AA AA AA AA AA AA 01 03 90 1F 01 D2 16------万能读表指令
    uart.write(1,
               string.char(0xFE, 0xFE, 0xFE, 0x68, 0x10, 0xAA, 0xAA, 0xAA, 0xAA,
                           0xAA, 0xAA, 0xAA, 0x01, 0x03, 0x90, 0x1F, 0x01, 0xD2,
                           0x16))
    sys.wait(500)

    uart.close(1)
    --meterno = meterno:match("^[%s]*(.-)[%s]*$")
    log.info("bh", meterno)

    if  meterno == nil then
        log.info("cs", rebootnum)
        if rebootnum <= 3 then
            log.info("reboot", rebootnum)
            uart.rxClear(1)
            rebootnum = rebootnum + 1
            fskv.set("rebootnum", rebootnum)
            if bauds == 9600 then
                bauds = 4800
                fskv.set("bauds", bauds)
                rtos.reboot()
            end
            if bauds == 4800 then
                bauds = 2400
                fskv.set("bauds", bauds)
                rtos.reboot()
            end
            if bauds == 2400 then
                bauds = 9600
                fskv.set("bauds", bauds)
                rtos.reboot()
            end
        end
    end

    

    sys.waitUntil("IP_READY", 30000)
    sys.publish("net_ready", device_id)
    local ret = sys.waitUntil("net_ready")
    local mycsq = mobile.rsrp()
    local yy = {DEVTYPE = "M2", SN = device_id, INFO = 4}
    local will_str = json.encode(yy)


    if ret then -----------------如果gprs网络已经连上ok
        local hh_now = string.sub(os.date("!%H:%M:%S",os.time()+28800),1,2)  -----获得当前整点时间
        local mm_now = string.sub(os.date("!%H:%M:%S",os.time()+28800),4,5)  -----获得当前分钟时间
        local ss_now = string.sub(os.date("!%H:%M:%S",os.time()+28800),7,8)  -----获得当前秒钟时间
        log.info("hh_now",hh_now)
        log.info("mm_now",mm_now)
        if senttime == 2400 then  -------如果设置为每个整点都上报
            if tonumber(mm_now)==0 then
                uptime = 60
            else
                uptime = 60 - tonumber(mm_now)
            end
        else
            uptime = tonumber(string.sub(senttime,1,2))*60 + tonumber(string.sub(senttime,3,4)) - (tonumber(hh_now)*60 + tonumber(mm_now))
            if uptime <= 0 then
                uptime = 24*60 - 1
            end
        end

        if meterno == nil then ----------------------------如果未能获得表号，说明水表接线或水表硬件故障
            if rebootnum > 3 then
                rebootnum = 0
                fskv.set("rebootnum", rebootnum)
            end
            local kk = {DEVTYPE = "M2", SN = device_id, INFO = 3}
            dev_data = json.encode(kk)
        else
            local dev_data0 = {
                DEVTYPE = "M0",
                SN = device_id,
                ICCID = ccid,
                --ALLDATA = alldata,
                METERNO = meterno,
                VER = "CB618-20240420",
                UPTIME = uptime,
                SENTTIME = senttime,
                REASON = reason,
                BATT = mybat,
                BAUD = bauds,
                METERSUM = metersum,
                PAYMODE = 1,
                RSRP = mobile.rsrp(),
                RSRQ = mobile.rsrq(),
                RSSI = mobile.rssi(),
                SINR = mobile.snr(),
                FACT = 1
            }
            dev_data = json.encode(dev_data0)
            -- local meter_data0 = {
            --     DEVTYPE = "M1",
            --     SN = device_id,
            --     METERSUM = metersum,
            --     PAYMODE = 1
            -- }
            -- meter_data = json.encode(meter_data0)
            -- local meter_data0 = {
            --     DEVTYPE = "M1",
            --     SN = device_id,
            --     METERSUM = metersum,
            --     PAYMODE = 1
            -- }
            -- meter_data = json.encode(meter_data0)
            --mqtt_client:publish(pub_topic, dev_data) ------上电联网成功后，发一条成功信息到订阅号
            --mqtt_client:publish(pub_topic, meter_data) ------联网成功后，将之前读到的水表数据发送到订阅号
        end





        -----log.info("times",os.date("!%Y-%m-%d %H:%M:%S",os.time()+28800))
        -----log.info("times",os.date("!%H:%M:%S",os.time()+28800))


        ----以下代码为定点上报，一天上报两次

        mqttc = mqtt.create(nil, mqtt_host, mqtt_port, mqtt_isssl, nil)
        mqttc:auth(client_id, user_name, password)
        mqttc:keepalive(30) ---------- 默认值240s
        mqttc:autoreconn(true, 3000) -- 自动重连机制
        mqttc:will(pub_topic, will_str)
        mqttc:on(
            function(mqtt_client, event, data, payload) -- 用户自定义代码
                if event == "conack" then -- 如果联上了
                    fls(12)
                    mqtt_client:subscribe(sub_topic) -- 单主题订阅
                    -- sys.wait(100)
                    
                    ---if meterno ~= nil then   ------------如果未取得表数据
                    mqtt_client:publish(pub_topic, dev_data)
                        --mqtt_client:publish(pub_topic, meter_data) ------联网成功后，将之前读到的水表数据发送到订阅号
                    --else
                    --    mqtt_client:publish(pub_topic, dev_data) ------上电联网成功后，发一条成功信息到订阅号
                    ---end
                end
                if event == "recv" then -- 如果收到下行数据
                    if payload ~= nil then
                        if string.sub(payload, 1, 2) == "D3" and string.sub(payload, 3, 17) == mobile.imei(0) then
                            if string.sub(payload, 18, 19) == "C4" then -- 设置自动上传周期 D3   869020066349869   C4   60(分钟)
                                uptime = string.sub(payload, 20, #payload)
                                if tonumber(uptime) >= 10 then
                                    fskv.set("uptime", uptime)
                                    local upt = fskv.get("uptime")
                                    local re = {
                                        DEVTYPE = "M3",
                                        SN = device_id,
                                        FUNCCODE = "C4",
                                        UPDATA = upt
                                    }
                                    local REDATA = json.encode(re)
                                    mqtt_client:publish(pub_topic, REDATA)
                                end
                            end
                            if string.sub(payload, 18, 19) == "T4" then  --------设置定点或整点上传时间 格式"小时分钟"---"2315"，如为2400，则每个整点上传一次
                                local re0 = nil
                                local temphm = string.sub(payload, 20, #payload)
                                if tonumber(string.sub(temphm,1,2))>24 or #temphm < 4 or tonumber(string.sub(temphm,3,4))>60 then 
                                    re0 = {
                                        DEVTYPE = "M3",
                                        SN = device_id,
                                        FUNCCODE = "T4",
                                        SENTTIME = "error"
                                    }
                                else
                                    senttime = temphm
                                    fskv.set("senttime",senttime)
                                    re0 = {
                                        DEVTYPE = "M3",
                                        SN = device_id,
                                        FUNCCODE = "T4",
                                        SENTTIME = senttime
                                    }
                                end
                                fskv.set("senttime", senttime)
                                local sst = fskv.get("senttime")
                                local re00 = json.encode(re0)
                                mqtt_client:publish(pub_topic, re00)
                            end

                        end
                    end
                end
            end)

    end
                
    sys.timerStart(function()
        mobile.flymode(0, true)
        log.info("深度休眠测试用DTIMER来唤醒")
        pm.dtimerStart(2, uptime * 60 * 1000)
        gpio.close(13)
        pm.force(pm.HIB)
        pm.power(pm.USB, false)
    end, wake_delay)

    mqttc:connect()
    sys.waitUntil("mqtt_conack")
    while true do sys.wait(uptime * 60 * 1000) end
    mqttc:close()
    mqttc = nil
end)

local function proc_get_meterno(strs)
    local k1 = string.sub(strs, 5, 18) --------获得水表表号原始数据
    local tmps = ""
    local tmplen = #k1 / 2 -- 获得字符长度
    for i = tmplen, 1, -1 do tmps = tmps .. string.sub(k1, 2 * i - 1, 2 * i) end
    return tmps
    -- local k2 = string.sub(strs,36,43) --------获得水表累计原始数据
end

local function proc_get_metersum(strs)
    local k2 = string.sub(strs, 29, 36) --------获得水表累计原始数据
    local tmps1 = ""
    local tmplen1 = #k2 / 2 -- 获得字符长度
    for i = tmplen1, 1, -1 do
        tmps1 = tmps1 .. string.sub(k2, 2 * i - 1, 2 * i)
    end
    --local str = "00123" -- 要处理的字符串
    local tmps2 = string.gsub(tmps1, "^%z+", "") -- 使用正则表达式将开头连续的零删除
    tmps2 = tonumber(tmps2*10)   --------DN300特殊表具*100，其他*10
    return tmps2
    -- local k2 = string.sub(strs,36,43) --------获得水表累计原始数据
end

uart.on(1, "receive", function(id, len)
    local s = ""
    repeat
        s = uart.read(id, len)
        alldata = s:toHex()
        if #s > 0 then -- #s 是取字符串的长度
            log.info("ss",ss)
            if string.sub(s:toHex(), 1, 4) == "FEFE" then
                local ss = string.gsub(s:toHex(), "FE", "")
                
                --if string.sub(ss,23,16) == "901F" then
                    meterno = proc_get_meterno(ss)
                    metersum = proc_get_metersum(ss)
                    fls(12)
                -- end
            end
        end
        if #s == len then break end
    until s == ""
end)

function fls(ints)
    gpio.setup(ints, 0)
    for i = 1, 1000 do gpio.set(ints, 0) end
    gpio.set(ints, 1)
    gpio.close(ints)
end

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
