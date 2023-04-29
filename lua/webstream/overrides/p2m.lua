hook.Add("InitPostEntity", "WebStream::InitP2M", function()
    if SERVER then
        function prop2mesh.sendDownload(pl, ent, crc)
            local data = ent.prop2mesh_partlists[crc]

            net.Start("prop2mesh_download")

            if WebStream and #data > 100000 and WebStream.Active:GetBool() then
                local id = "WS::" .. crc .. "." .. SysTime()
                net.WriteString(id)
                net.WriteString(crc)
                WebStream.WriteStream(id, data)
            else
                net.WriteString(crc)
                prop2mesh.WriteStream(data)
            end

            net.Send(pl)
        end
    else
        net.Receive("prop2mesh_download", function()
            local id = net.ReadString()

            prop2mesh.downloads = prop2mesh.downloads + 1

            if string.sub(id, 1, 4) == "WS::" then
                local crc = net.ReadString()

                WebStream.ReadStream(id, function(data)
                    prop2mesh.handleDownload(crc, data)
                end)
            else
                if not id then
                    prop2mesh.downloads = prop2mesh.downloads - 1

                    return
                end

                prop2mesh.ReadStream(nil, function(data)
                    prop2mesh.handleDownload(id, data)
                end)
            end
        end)
    end
end)