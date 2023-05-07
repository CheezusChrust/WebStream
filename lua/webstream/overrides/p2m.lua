hook.Add("InitPostEntity", "WebStream::InitP2M", function()
    if SERVER then
        local function sendNormal(crc, data)
            net.WriteString(crc)
            prop2mesh.WriteStream(data)
        end

        local function sendWebstream(crc, data, pl)
            local id = "WS::" .. crc .. "." .. SysTime()
            net.WriteString(id)
            net.WriteString(crc)
            WebStream.WriteStream(id, data, pl)
        end

        function prop2mesh.sendDownload(pl, ent, crc)
            local data = ent.prop2mesh_partlists[crc]

            net.Start("prop2mesh_download")

            if WebStream and #data > 25000 and GetConVar("webstream_active_sv"):GetBool() and pl:GetInfoNum("webstream_active_cl", 0) == 1 then
                sendWebstream(crc, data, pl)
            else
                sendNormal(crc, data)
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