local lbsLoc2 = require("lbsLoc2")   ------定位库
local reason, slp_state = pm.lastReson()  --获取唤醒原因
gpio.setup(11,1)   ----INA   电机阀控制脚
gpio.setup(8,1) -------INB   电机阀控制脚
adc.open(adc.CH_VBAT)
local mybat = adc.get(adc.CH_VBAT)
adc.close(adc.CH_VBAT)
---pm.power(pm.WORK_MODE,1)
---local lat, lng, t
if fskv.get("bauds") == nil then
    fskv.set("bauds", 9600) ------- 设置默认波特率
    fskv.set("uptime", 60) ------- 设置自动上传周期，默认60分钟【单位分钟】
    fskv.set("recharsum", 0) -------- + 设置预付费表充值累计数
    fskv.set("alarmint", 1000) ----- + 预警量 ALARMINT
    fskv.set("valstate",5) -------  设置阀门状态，11开，22关，33卡住
    fskv.set("rebootnum", 4)
end
if fskv.get("valstate") == 5 then
    if gpio.get(3) == 1 and gpio.get(6) == 0 then  -----阀门开到位gpio指示
        valstate = 11
    end
    if gpio.get(3) == 0 and gpio.get(6) == 1 then  -----阀门关到位gpio指示
        valstate = 22
    end
    if gpio.get(3) == 0 and gpio.get(6) == 0 then  -----阀门卡住gpio指示
        valstate = 44
    end
end
fskv.set("valstate",valstate)
--pm.power(pm.WORK_MODE,1)
local lat, lng, t
local alarmnum = 0
local close_num = 0
local dev_data = nil
local meter_data = nil
local remain = 0   --------预付费剩余值
local alarmint = fskv.get("alarmint")
local recharsum = fskv.get("recharsum")
local rebootnum = fskv.get("rebootnum")
local mqtt_host = "mqtt.yihuan100.com"
local mqtt_port = 1883
local mqtt_isssl = false
local client_id = "AIR780E-" .. mobile.imei(0)
local user_name = "test001"
local password = "test1234"
local meterno = nil  -------水表表号
----local recharsum = fskv.get("recharsum")
---local valstate = fskv.get("valstate")  -------阀门状态
local valstate = fskv.get("valstate")  -------阀门状态



---log.info("zt",valstate)

local alldata = nil
local metersum = ""        ----水表表头的实际累计数【表头读数】
local pub_topic = "yomtey/prod/s/" .. mobile.imei(0)  ----mqtt发送主题
local sub_topic = "yomtey/prod/p/" .. mobile.imei(0)  ----mqtt订阅主题

local mqttc = nil
local bauds = fskv.get("bauds") --------获得波特率
local uptime = fskv.get("uptime") --------获得自动上传周期
local device_id = mobile.imei(0)  ------获得序列号【imei号】
local ccid = mobile.iccid(0)      ------获得iccid号
local table_baud = {9600,4800,2400}   ------波特率范围
local i = 1
gpio.setup(11,0)   ----INA   电机阀控制脚
gpio.setup(8,0) -------INB   电机阀控制脚

uart.setup(1, bauds, 8, 1, uart.EVEN)

sys.taskInit(function()
    --pm.power(pm.WORK_MODE,1)
    gpio.setup(23, nil)
    gpio.close(12)
    --gpio.close(13)

    gpio.close(33) --如果功耗偏高，开始尝试关闭WAKEUPPAD1
    gpio.close(32) -- 如果功耗偏高，开始尝试关闭WAKEUPPAD0
    --gpio.setup(32, function() end, gpio.PULLUP)
    gpio.close(35) -- 这里pwrkey接地才需要，不接地通过按键控制的不需要
    log.info("bauds", bauds)
    --uart.setup(1, bauds, 8, 1, uart.EVEN)
    gpio.setup(13,1)
    sys.wait(100)
    -- FE FE FE 68 10 AA AA AA AA AA AA AA 01 03 90 1F 01 D2 16------万能读表指令
    uart.write(1,string.char(0xFE, 0xFE, 0xFE, 0x68, 0x10, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0x01, 0x03, 0x90, 0x1F, 0x01, 0xD2, 0x16))
    sys.wait(500)

    --uart.close(1)
    --meterno = meterno:match("^[%s]*(.-)[%s]*$")----
    log.info("bh", meterno)
    if  meterno == nil then
        log.info("cs", rebootnum)
        if rebootnum <= 4 then
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

    local yy = {DEVTYPE = "M2", SN = device_id, INFO = 4}  ---mqtt遗言数据
    local will_str = json.encode(yy)      ---mqtt遗言json格式
    


    if meterno == nil then ----------------------------如果未能获得表号，说明水表接线或水表硬件故障
        if rebootnum > 3 then
            rebootnum = 0
            fskv.set("rebootnum", rebootnum)
        end
        local kk = {DEVTYPE = "M2", SN = device_id, INFO = 3}
        dev_data = json.encode(kk)

        
    else
        upCellInfo()
        -----首先判断设备的余额，来决定阀门状态
        remain = tonumber(recharsum) - tonumber(metersum) ------获得剩余流量
        
        local dev_data0 = {
            DEVTYPE = "M0",
            SN = device_id,
            ICCID = ccid,
            --ALLDATA = alldata,
            METERNO = meterno,
            VER = "MCD618-20240715",
            UPTIME = uptime,
            REASON = reason,
            VALSTATE = valstate,
            BATT = mybat,
            BAUD = bauds,
            LAT = lat,
            LNG = lng,
            RSRP = mobile.rsrp(),
            RSRQ = mobile.rsrq(),
            RSSI = mobile.rssi(),
            SINR = mobile.snr(),
            --FACT = 1
        }
        dev_data = json.encode(dev_data0)
        local meter_data0 = {
            DEVTYPE = "M1",
            SN = device_id,
            METERSUM = tonumber(metersum),
            ALARMINT = alarmint,
            RECHARSUM = recharsum,
            REMAIN = remain,
            PAYMODE = 1
        }
        meter_data = json.encode(meter_data0)
    end
    log.info("RET",ret)
    if ret then -----------------如果gprs网络已经连上ok
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
                    if meterno ~= nil then   ------------如果未取得表数据
                        mqtt_client:publish(pub_topic, dev_data)
                        mqtt_client:publish(pub_topic, meter_data) ------联网成功后，将之前读到的水表数据发送到订阅号
                    else
                        mqtt_client:publish(pub_topic, dev_data) ------上电联网成功后，发一条成功信息到订阅号
                    end
                elseif event == "recv" then
                    sys.publish("mqtt_payload", data, payload)  ------系统通知，收到MQTT下行指令
                end
            end)
    else
        rtos.reboot()  ----如果未连上网络，重启模组
    end
    -- ec618的节能模式，0~3，0完全关闭，1性能优先，2平衡，3极致功耗
    -- 详情访问: https://airpsm.cn
    -- pm.power(pm.WORK_MODE, 1)


    sys.timerStart(function()
        mobile.flymode(0, true)
        log.info("深度休眠测试用DTIMER来唤醒")
        pm.dtimerStart(2, uptime * 60 * 1000)
        gpio.setup(13,0)
        gpio.close(13)
        pm.force(pm.HIB)
        pm.power(pm.USB, false)
    end, wake_delay)


    mqttc:connect()
    sys.waitUntil("mqtt_conack")
    while true do sys.wait(600000) end
    ---gpio.close(13)
    mqttc:close()
    mqttc = nil
end)

-- sys.taskInit(function()   ------周期上传mqtt数据
-- 	--local data = "123,"
--     --pm.power(pm.WORK_MODE,1)
-- 	local qos = 0 -- QOS0不带puback, QOS1是带puback的
--     while true do
--         sys.wait(uptime * 60 * 1000)
--         if mqttc and mqttc:ready() then
--            --- gpio.setup(13,0)
--             ---sys.wait(200)
--             uart.write(1,string.char(0xFE, 0xFE, 0xFE, 0x68, 0x10, 0xAA, 0xAA, 0xAA, 0xAA,0xAA, 0xAA, 0xAA, 0x01, 0x03, 0x90, 0x1F, 0x01, 0xD2, 0x16))
--             if metersum ~= nil then
--                 remain = tonumber(recharsum) - tonumber(metersum) ------获得剩余流量
--                 local meter_data0 = {
--                     DEVTYPE = "M1",
--                     SN = device_id,
--                     METERSUM = metersum,
--                     ALARMINT = alarmint,
--                     RECHARSUM = fskv.get("recharsum"),
--                     REMAIN = remain,
--                     PAYMODE = 2
--                 }
--                 meter_data = json.encode(meter_data0)
--             local pkgid = mqttc:publish(pub_topic, meter_data)
--             end
--             ---gpio.close(13)
--         end
--     end
-- end)

--[[ sys.taskInit(function()   ------周期检测充值剩余量
    while true do
        sys.wait(60000)
        if mqttc and mqttc:ready() then
            local pkgid = mqttc:publish(pub_topic, meter_data)
        end
    end

end) ]]



sys.taskInit(function() ------周期检测预付费剩余量
    --pm.power(pm.WORK_MODE,1)
    
    local mess0 = ""
    local mess = ""
    while true do
        sys.wait(30000)
        gpio.setup(13,1)
        sys.wait(200)
        uart.write(1,string.char(0xFE, 0xFE, 0xFE, 0x68, 0x10, 0xAA, 0xAA, 0xAA, 0xAA,0xAA, 0xAA, 0xAA, 0x01, 0x03, 0x90, 0x1F, 0x01, 0xD2, 0x16))
        sys.wait(200)
        if metersum ~= nil then
            recharsum = fskv.get("recharsum")   ----获得累计充值量
            alarmint = fskv.get("alarmint")     ----获得预警量
            remain = recharsum - tonumber(metersum)   -----获得充值剩余量
            log.info("recharsum",tonumber(recharsum))
            log.info("metersum",tonumber(metersum))
            log.info("remain",remain)
            log.info("alarmint",alarmint)
            if remain <= alarmint and alarmnum < 3 then -----剩余量小于等于预警量
                alarmnum = alarmnum + 1
                mess0 = {DEVTYPE = "M2", SN = device_id, INFO = 2}
                mess = json.encode(mess0)
                mqtt_client:publish(pub_topic, mess)  ---------发出余额预警的信息
            end
            valstate = fskv.get("valstate")
            if remain <= 0 and close_num == 0 then ------------充值累计已经用完,执行关阀动作
                close_num = close_num + 1
                mess0 = {DEVTYPE = "M2", SN = device_id, INFO = 33}   ---------发出余额用完的信息
                mess = json.encode(mess0)
                sys.timerStart(function()
                    ---print("延时后执行的操作")
                    -- 在这里放置需要延时后执行的代码
                    mqtt_client:publish(pub_topic, mess)
                end, 500)
                
                if valstate ~= 22 then
                    Switch_proc("autoclose")
                end
            end
        end
        gpio.setup(13,0)
        gpio.close(13)
    end



end)



sys.subscribe("mqtt_payload",function(topic, payload)
    --log.info("uart", "uart发送数据长度", #payload)
    local dev_data0 = ""
    local dev_data = ""

    fls(12)
    if payload ~= nil then
        if string.sub(payload, 1, 2) == "D3" and string.sub(payload, 3, 17) == mobile.imei(0) then
            local bup0 = nil
            local updata2 = nil
            if string.sub(payload, 18, 19) == "C4" then  ------ 设置自动上传周期D3867713070630363C40000000060 D3   869020066349869   C4   60(分钟)
                --bup0 = string.sub(payload, 20, #payload)
                uptime = string.gsub(bup0, "^%z+", "") --- 使用正则表达式将开头连续的零删除
                if tonumber(uptime) >= 1 then
                fskv.set("uptime", uptime)
                local upt = fskv.get("uptime")
                dev_data0  = {
                            DEVTYPE = "M3",
                            SN = device_id,
                            FUNCCODE = "C4",
                            UPDATA = upt
                            }
                dev_data = json.encode(dev_data0)
                mqtt_client:publish(pub_topic, dev_data)
                --local upt = fskv.get("uptime")
                --mqttc:publish(pub_topic, "M3"..mobile.imei(0).."C4"..bup0)
                end
            end
            if string.sub(payload, 18, 19) == "A3" then  -------查询业务数据  D3867713070630363A2----------
                log.info("payload", payload)
                log.info("A2", string.sub(payload, 18, 19))
                gpio.setup(13,1)
                sys.timerStart(function()
                    ---print("延时后执行的操作")
                    -- 在这里放置需要延时后执行的代码
                    uart.write(1,string.char(0xFE, 0xFE, 0xFE, 0x68, 0x10, 0xAA, 0xAA, 0xAA, 0xAA,0xAA, 0xAA, 0xAA, 0x01, 0x03, 0x90, 0x1F, 0x01, 0xD2, 0x16))
                    if metersum ~= nil then
                        --    log.info("leiji",metersum)
                        ------先生成业务数据json
                        remain = tonumber(recharsum) - tonumber(metersum) ------获得剩余流量
                        updata2 = {METERSUM = tonumber(metersum),
                                ALARMINT = alarmint,
                                RECHARSUM = fskv.get("recharsum"),
                                REMAIN = remain
                                }
                        dev_data0 = {DEVTYPE = "M3",
                                SN = device_id,
                                UPDATA2 = updata2,
                                FUNCCODE = "A3",
                                }
                        dev_data = json.encode(dev_data0)
                        mqtt_client:publish(pub_topic, dev_data)
                    end
                end, 200)
                gpio.setup(13,0)
                gpio.close(13)

            end
            if string.sub(payload, 18, 19) == "A4" then --  查询设备参数   D3867713070630363A3  ----------
                upCellInfo()
                adc.open(adc.CH_VBAT)
                mybat = adc.get(adc.CH_VBAT)
                adc.close(adc.CH_VBAT)
                log.info("valstate",valstate)
                updata2 = {
                    METERNO = meterno,
                    ICCID = ccid,
                    VER = "MCD618-20240715",
                    UPTIME = uptime,
                    ---REASON = reason,
                    VALSTATE = valstate,
                    PAYMODE = 2,
                    BATT = mybat,
                    BAUD = bauds,
                    LAT = lat,
                    LNG = lng,
                    RSRP = mobile.rsrp(),
                    RSRQ = mobile.rsrq(),
                    RSSI = mobile.rssi(),
                    SINR = mobile.snr()
                }

                dev_data0 = {
                    DEVTYPE = "M3",
                    SN = device_id,
                    UPDATA2 = updata2,
                    --FACT = 1,
                    FUNCCODE = "A4"
                }
                dev_data = json.encode(dev_data0)
                ---log.info("dev_data",dev_data)
                mqtt_client:publish(pub_topic, dev_data)
            end


            if string.sub(payload, 18, 19) == "B1" then -------------------充值或清零
                bup0 = string.sub(payload, 20, #payload)
                recharsum = fskv.get("recharsum")
                alarmint = fskv.get("alarmint")


                ---先要取一次表头累计数metersum

                if bup0 ~= "" then
                    if tonumber(bup0) > 0 then -----如果充值数大于0
                        ----local recharsum0 = tonumber(recharsum) + tonumber(bup0)  -----本次充值数加上以前的充值累计数
                        local recharsum0 = tonumber(bup0)  -----
                        fskv.set("recharsum", recharsum0)
                        recharsum = recharsum0
                        close_num = 0
                        ----------发送充值成功信息
                        dev_data0 = {
                            DEVTYPE = "M3",
                            SN = device_id,
                            ICCID = ccid,
                            FUNCCODE = "B1",
                            UPDATA = recharsum0
                        }
                        dev_data = json.encode(dev_data0)
                        mqtt_client:publish(pub_topic, dev_data)

                        sys.timerStart(function()
                        --     ---print("延时后执行的操作")
                        --     -- 在这里放置需要延时后执行的代码
                            remain = recharsum - tonumber(metersum) ------ 得到余额
                            if remain > tonumber(alarmint) then ----- 如果余额大于预警值则解除预警状态
                                alarmnum = 0
                                dev_data0 = {DEVTYPE = "M2", SN = device_id, INFO = 1}
                                dev_data = json.encode(dev_data0)
                                mqtt_client:publish(pub_topic, dev_data)
                            end
                        end, 500)

                        sys.timerStart(function()
                            ---print("延时后执行的操作")
                            -- 在这里放置需要延时后执行的代码
                            dev_data0 = {DEVTYPE = "M2", SN = device_id, INFO = 11}
                            dev_data = json.encode(dev_data0)
                            mqtt_client:publish(pub_topic, dev_data)
                        end, 500)

                        if tonumber(recharsum) - tonumber(metersum) >= 0 then ----------如果充值满足开阀要求
                            if tonumber(valstate) == 33 then ----------如果之前阀门是因欠费而关闭的
                                Switch_proc("autoopen")
                            end
                        end
                    end
                else
                    fskv.set("recharsum", 0)
                    recharsum = 0

                    dev_data0 = {
                        DEVTYPE = "M3",
                        SN = device_id,
                        ICCID = ccid,
                        FUNCCODE = "B1",
                        UPDATA = 0
                    }
                    dev_data = json.encode(dev_data0)
                    mqtt_client:publish(pub_topic, dev_data)
                end
            end




            if string.sub(payload, 18, 19) == "C5" then --  开阀或关阀   D3867713070630363C50000000001  ----------
                bup0 = string.sub(payload, 20, #payload)
                if bup0 == "11" then  ------强制开阀
                    if valstate ~= 33 then  ------如果不是欠费关阀
                        Switch_proc("open")
                    end
                end
                if bup0 == "22" then  ------强制关阀
                    Switch_proc("close")
                end
            end
        end
    end
end)
-----gpio去抖动

sys.subscribe("do_switch",function(sws)   ----------捕获开关阀是否成功
    local moto_status0 = nil  
    log.info("sws",sws)
    if sws == "k0" then  -------最终电机已开到位
        valstate = 11
        moto_status0 ={
            DEVTYPE = "M3",
            SN = device_id,
            FUNCCODE = "C5",
            UPDATA =11
        }
    end
    if sws == "ak0" then  -------最终电机已开到位,充值自动开阀
        valstate = 11
        moto_status0 ={
            DEVTYPE = "M2",
            SN = device_id,
            INFO = 11
        }
    end
    if sws == "k1" then  -------最终电机未开到位
        valstate = 44
        moto_status0 ={
            DEVTYPE = "M3",
            SN = device_id,
            FUNCCODE = "C5",
            UPDATA = 44
        }
    end
    if sws == "g0" then  -------最终电机已关到位
        valstate = 22
        moto_status0 ={
            DEVTYPE = "M3",
            SN = device_id,
            FUNCCODE = "C5",
            UPDATA = 22
        }
    end
    if sws == "ag0" then  -------最终电机自动已关到位【欠费关阀】
        valstate = 33
        moto_status0 ={
            DEVTYPE = "M2",
            SN = device_id,
            INFO = 33
        }
    end
    if sws == "g1" or sws == "ag1" then  -------最终电机未关到位
        valstate = 44
        moto_status0 ={
            DEVTYPE = "M3",
            SN = device_id,
            FUNCCODE = "C5",
            UPDATA = 44
        }
    end
    fskv.set("valstate",valstate)
    valstate = fskv.get("valstate")
    log.info("vvv",valstate)
    local moto_status = json.encode(moto_status0)
    mqtt_client:publish(pub_topic, moto_status)     ------发送到MQTT
end)



function Switch_proc(strs)    ------开关阀函数
    local sws = nil
    local timeout = 30
    local startTime = os.clock()
    ---pm.power(pm.WORK_MODE,0)
    gpio.setup(13,1)
    if strs == "open" then
        while gpio.get(3) == 0 do    ---电机未开到位  gpio3为行程开关到位指示 Y
            gpio.setup(11,1)   ----INA   电机阀控制脚
            gpio.setup(8,0) -------INB   电机阀控制脚
            gpio.setup(12,0) ------------电机动作指示灯亮
            if os.clock() - startTime > timeout then  -----超时退出
                break
            end
        end
        if gpio.get(3) == 0 then  
            sws = "k1"  -------最终电机未开到位
        else
            sws = "k0"  -------最终电机已开到位
        end
        gpio.setup(8,1) -------INB   电机阀控制脚
        gpio.setup(12,1) ------------电机动作指示灯灭
    end
    if strs == "autoopen" then
        while gpio.get(3) == 0 do    ---电机未开到位  gpio3为行程开关到位指示 Y
            gpio.setup(11,1)   ----INA   电机阀控制脚
            gpio.setup(8,0) -------INB   电机阀控制脚
            gpio.setup(12,0) ------------电机动作指示灯亮
            if os.clock() - startTime > timeout then  -----超时退出
                break
            end
        end
        if gpio.get(3) == 0 then  
            sws = "ak1"  -------最终电机未开到位
        else
            sws = "ak0"  -------最终电机已开到位
        end
        gpio.setup(8,1) -------INB   电机阀控制脚
        gpio.setup(12,1) ------------电机动作指示灯灭
    end
    if strs == "close" then
        while gpio.get(6) == 0 do    ---电机未关到位  gpio6为 B
            gpio.setup(11,0)   ----INA   电机阀控制脚
            gpio.setup(8,1) -------INB   电机阀控制脚
            gpio.setup(12,0) ------------ 电机动作指示灯亮
            if os.clock() - startTime > timeout then  -----超时退出
                break
            end
        end
        if gpio.get(6) == 0 then  
            sws = "g1"  -------最终电机未关到位
        else
            sws = "g0"  -------最终电机已关到位
        end
        gpio.setup(11,1) -------INA   电机阀控制脚
        gpio.setup(12,1) ------------电机动作指示灯灭
    end
    if strs == "autoclose" then
        while gpio.get(6) == 0 do    ---电机未关到位  gpio6为 B
            gpio.setup(11,0)   ----INA   电机阀控制脚
            gpio.setup(8,1) -------INB   电机阀控制脚
            gpio.setup(12,0) ------------ 电机动作指示灯亮
            if os.clock() - startTime > timeout then  -----超时退出
                break
            end
        end
        if gpio.get(6) == 0 then  
            sws = "ag1"  -------最终电机未关到位
        else
            sws = "ag0"  -------最终电机已关到位
        end
        gpio.setup(11,1) -------INA   电机阀控制脚
        gpio.setup(12,1) ------------电机动作指示灯灭
    end
    gpio.setup(13,0)
    gpio.close(13)
    ---pm.power(pm.WORK_MODE,1)
    sys.publish("do_switch",sws)
end


local function proc_get_meterno(strs)
    local k1 = string.sub(strs, 5, 18) --------获得水表表号原始数据6810891070800000008116901F01000000002C000000002C0000000000000000FF9F16
    local tmps = ""
    local tmplen = #k1 / 2 -- 获得字符长度
    for i = tmplen, 1, -1 do tmps = tmps .. string.sub(k1, 2 * i - 1, 2 * i) end
    return tmps
    -- local k2 = string.sub(strs,36,43) --------获得水表累计原始数据
    --log.info("meterno",tmps)
end

local function proc_get_metersum(strs)
    local k2 = string.sub(strs, 29, 36) --------获得水表累计原始数据  6810670517240000008116901F01000300002C000300002C0000000000000000FFC316

    local tmps1 = ""
    local tmps2 = ""
    local tmplen1 = #k2 / 2 -- 获得字符长度
    for i = tmplen1, 1, -1 do
        tmps1 = tmps1 .. string.sub(k2, 2 * i - 1, 2 * i)
    end
    --local str = "00123" -- 要处理的字符串
    --= string.gsub(tmps1, "^%z+", "") --- 使用正则表达式将开头连续的零删除
    if tonumber(tmps1) ~= 0 then
        tmps2 = tmps1:match("^[0]*(.-)[%s]*$")--- 使用正则表达式将开头连续的零删除
    else
        tmps2 = tmps1
    end
    
    log.info("tmps1",tmps1)
    log.info("tmps2",tmps2)
    ---- tmps2 = tonumber(tmps2)*10   -------- DN300特殊表具*100，其他*10
    if #tmps2 < 9 then
        local jjj = 9 - #tmps2
        tmps2 = string.rep("0",jjj) .. tmps2.."0"    ----不足10位的累计，前面补零直到满足10位
    end
    return tmps2
    -- local k2 = string.sub(strs,36,43) -------- 获得水表累计原始数据
end



function upCellInfo()   -------基站定位函数
    ----log.info('请求基站查询')
    mobile.reqCellInfo(15)
    ----log.info('开始查询基站定位信息')
    sys.waitUntil("CELL_INFO_UPDATE", 10000)
    lat, lng, t = lbsLoc2.request(5000,nil,nil,true)
    if lat ~= nil then
    -- 这里的时间戳需要减 28800 北京时间 
        --log.info("定位成功",lat, lng, os.time(t),(json.encode(t or {})))
        return lat,lng
    else
        --log.info("基站定位失败")
        return nil
    end
end 


uart.on(1, "receive", function(id, len)
    local s = ""
    repeat
        s = uart.read(id, len)
        alldata = s:toHex()
        if #s > 0 then -- #s 是取字符串的长度
            
            if string.sub(s:toHex(), 1, 4) == "FEFE" then
                local ss = string.gsub(s:toHex(), "FE", "")
                log.info("ss",ss)
                if string.sub(ss,23,26) == "901F" then --6810891070800000008116901F01000000002C000000002C0000000000000000FF9F16
                    meterno = proc_get_meterno(ss)
                    metersum = proc_get_metersum(ss)
                    fls(12)
                end
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
