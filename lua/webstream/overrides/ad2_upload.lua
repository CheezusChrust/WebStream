hook.Add("InitPostEntity", "WebStream::InitAd2Upload", function()
    if CLIENT then
        local uploading = nil

        local function sendNormal(name, read)
            net.WriteString(name)

            uploading = net.WriteStream(read, function()
                uploading = nil
                AdvDupe2.File = nil
                AdvDupe2.RemoveProgressBar()
            end)
        end

        local function sendWebstream(name, read)
            local randID = "WS::" .. math.random() .. "." .. SysTime()

            net.WriteString(randID)
            net.WriteString(name)

            uploading = WebStream.WriteStream(randID, read, nil, function()
                uploading = nil
                AdvDupe2.File = nil
                AdvDupe2.RemoveProgressBar()
            end, function()
                uploading = nil
                AdvDupe2.File = nil
                AdvDupe2.RemoveProgressBar()
            end)
        end

        function AdvDupe2.UploadFile(ReadPath, ReadArea)
            if uploading then
                AdvDupe2.Notify("Already opening file, please wait.", NOTIFY_ERROR)

                return
            end

            if ReadArea == 0 then
                ReadPath = AdvDupe2.DataFolder .. "/" .. ReadPath .. ".txt"
            elseif ReadArea == 1 then
                ReadPath = AdvDupe2.DataFolder .. "/-Public-/" .. ReadPath .. ".txt"
            else
                ReadPath = "adv_duplicator/" .. ReadPath .. ".txt"
            end

            if not file.Exists(ReadPath, "DATA") then
                AdvDupe2.Notify("File does not exist", NOTIFY_ERROR)

                return
            end

            local read = file.Read(ReadPath)

            if not read then
                AdvDupe2.Notify("File could not be read", NOTIFY_ERROR)

                return
            end

            local name = string.Explode("/", ReadPath)
            name = name[#name]
            name = string.sub(name, 1, #name - 4)
            local success, dupe, info, moreinfo = AdvDupe2.Decode(read)
            local filesize = #read

            if success then
                net.Start("AdvDupe2_ReceiveFile")

                if WebStream and filesize > 100000 and GetConVar("webstream_active_sv"):GetBool() and GetConVar("webstream_active_cl"):GetBool() then
                    sendWebstream(name, read)
                else
                    sendNormal(name, read)
                end

                net.SendToServer()

                AdvDupe2.LoadGhosts(dupe, info, moreinfo, name)
            else
                AdvDupe2.Notify("File could not be decoded. (" .. dupe .. ") Upload Canceled.", NOTIFY_ERROR)
            end
        end
    else
        local function parseUpload(ply, data)
            if data then
                AdvDupe2.LoadDupe(ply, AdvDupe2.Decode(data))
            else
                AdvDupe2.Notify(ply, "Duplicator Upload Failed!", NOTIFY_ERROR, 5)
            end

            ply.AdvDupe2.Uploading = false
        end

        local function AdvDupe2_ReceiveFile(_, ply)
            if not IsValid(ply) then return end

            if not ply.AdvDupe2 then
                ply.AdvDupe2 = {}
            end

            local data1 = net.ReadString()
            local stream

            if string.sub(data1, 1, 4) == "WS::" then
                ply.AdvDupe2.Name = string.match(net.ReadString(), "([%w_ ]+)") or "Advanced Duplication"

                stream = WebStream.ReadStream(data1, function(data)
                    parseUpload(ply, data)
                end, function()
                    AdvDupe2.Notify(ply, "Duplicator Upload Failed!", NOTIFY_ERROR, 5)

                    ply.AdvDupe2.Uploading = false
                end)
            else
                ply.AdvDupe2.Name = string.match(data1, "([%w_ ]+)") or "Advanced Duplication"

                stream = net.ReadStream(ply, function(data)
                    parseUpload(ply, data)
                end)
            end

            if ply.AdvDupe2.Uploading then
                if stream then
                    stream:Remove()
                end

                AdvDupe2.Notify(ply, "Duplicator is Busy!", NOTIFY_ERROR, 5)
            elseif stream then
                ply.AdvDupe2.Uploading = true
                AdvDupe2.InitProgressBar(ply, "Opening: ")
            end
        end

        net.Receive("AdvDupe2_ReceiveFile", AdvDupe2_ReceiveFile)
    end
end)