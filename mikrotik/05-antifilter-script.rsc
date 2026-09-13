# ============================================================
#  Antifilter: загрузка готового .rsc из GitHub
#  Требует workflow gen-rsc.yml в репозитории
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

/system/scheduler
add name=antifilter-update interval=1d start-time=04:00:00 \
    on-event=update-antifilter comment="Daily antifilter refresh"
