# ============================================================
#  СПОСОБ A (РЕКОМЕНДУЕТСЯ): тянуть готовый .rsc из GitHub
#  Не грузит CPU парсингом. Требует workflow antifilter.yml
# ============================================================
/system/script
add name=update-antifilter dont-require-permissions=no \
    policy=read,write,test,ftp source={
    :log info "antifilter: fetching prebuilt rsc"
    :do {
        /tool/fetch \
            url="https://raw.githubusercontent.com/3VwVnts/byedpi-mikrotik/main/dist/antifilter.rsc" \
            mode=https dst-path=antifilter.rsc
        :delay 3s
        /import file-name=antifilter.rsc
        :log info "antifilter: imported OK"
    } on-error={
        :log error "antifilter: update failed"
    }
}

# ============================================================
#  СПОСОБ B (fallback): парсить ipsmart.lst на роутере
#  Медленнее, грузит CPU. Раскомментируйте если не хотите GitHub.
# ============================================================
# /system/script
# add name=update-antifilter-local dont-require-permissions=no \
#     policy=read,write,test source={
#     :local listName "za_dpi_FWD"
#     :do {
#         /tool/fetch url="https://antifilter.download/list/ipsmart.lst" \
#             mode=https dst-path=antifilter.lst
#     } on-error={ :log error "fetch failed"; :return }
#     :delay 3s
#     /ip/firewall/address-list remove [find list=$listName]
#     :local content [/file/get antifilter.lst contents]
#     :local line ""
#     :local i 0
#     :local len [:len $content]
#     :while ($i < $len) do={
#         :local ch [:pick $content $i ($i+1)]
#         :if ($ch = "\n") do={
#             :if ([:len $line] > 6) do={
#                 :do { /ip/firewall/address-list add list=$listName address=$line } on-error={}
#             }
#             :set line ""
#         } else={ :set line ($line . $ch) }
#         :set i ($i + 1)
#     }
#     :log info "antifilter: local parse done"
# }

# ===== Планировщик: обновление списка ежедневно =====
/system/scheduler
add name=antifilter-update interval=1d start-time=04:00:00 \
    on-event=update-antifilter comment="Daily antifilter refresh"
