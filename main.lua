PROJECT = "M-CB-780"
VERSION = "1.0.0"    ------------6系列代表用粤镁特的项目标识烧录恒通的代码
----VERSION = "2.0.0"    ------------------- 深圳测试客户用户 mqtt_DC_SZ
---PRODUCT_KEY = "emus4VDXBdNFLPOh9soTnr4mBuI6Z5dc"   --------- 深圳测试客户用
---PRODUCT_KEY = "JacQ2Y5Kiru3nhr19tBAvGl6gNmbm8CK" ----------- 【公司演示】光电485有源带阀
---PRODUCT_KEY = "pjsuFjPr1yfs8s11pEXHJxsB4mK7T6ec" ----------- 【公司演示】光电485电池无阀
----PRODUCT_KEY = "m7dHQUYd4qHO3zD1JgWfjDZr5ToiHQMD" ----------【浙江恒通】光电485电池无阀
----PRODUCT_KEY = "q4L8GTRWjJ6dpsoKxjRjgBGdZFD8cpWA"   --------- 公司485后付费电池水表 2.0.3
----PRODUCT_KEY = "zqdsJodk0d2qWDkTHyLOc081PVBB2ZMw"   --------【公司演示】光电485有源无阀  2.0.5
PRODUCT_KEY = "If6T9YGWt7MERAN3Mw1Un1Bk5JvkCx5S"  ------------【业务模式】Air780E-485电池带阀 1.0.0
-- sys库是标配
_G.sys = require("sys")
fskv.init()
mobile.flymode(0,false)

libnet = require "libnet"
libfota = require "libfota"


--[[ sys.taskInit(function()
    while 1 do
        sys.wait(1000)
        log.info("fota","VER",VERSION)
        log.info("hello world!",VERSION)
    end
end) ]]

function fota_cb(ret)
    log.info("fota", ret)
    if ret == 0 then
        rtos.reboot()
    end
end

libfota.request(fota_cb)
sys.timerLoopStart(libfota.request, 3600000, fota_cb)
----require("mqtt_DC_SZ202405")  ------深圳测试客户用
---require("mqtt_DC_SZ")  ------深圳测试客户用
---require("mqtt_DC_SW")   ------【公司演示】光电485有源带阀
---require("mqtt_BA")    ---- 公司485后付费电池水表 2.0.3
---require("mqtt_BA_HT")     ------【浙江恒通】光电485电池无阀
----require("mqtt_DC")
----_G.sysplus = require("sysplus")
---require("mqtt_BA_SW_PR")   ------【业务模式】Air780E-485电池带阀 1.0.0
require("mqtt_BA_SW_SK_PR")   ------【业务模式】Air780E-485电池带阀山科 1.0.0


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!