hook.Add("InitPostEntity", "WebStream::InitAd2Download", function()
    if SERVER then
        util.AddNetworkString("WebStream::AdvDupe2::FileReadyDownload")

        local download

        local function sendNormal(data, ply)
            net.WriteString("")
            download = net.WriteStream(data, function()
                ply.AdvDupe2.Downloading = false
                download = nil
            end)

            timer.Create("AdvDupe2::DownloadProgress", 0.25, 0, function()
                if not download then
                    timer.Remove("AdvDupe2::DownloadProgress")

                    return
                end

                local progress = 0
                local client = next(download.clients)
                if client then
                    client = download.clients[client]

                    if client.progress then
                        progress = client.progress / download.numchunks
                    end
                end

                AdvDupe2.UpdateProgressBar(ply, progress * 100)
            end)
        end

        local function sendWebstream(data, ply)
            local randID = "WS::" .. math.random() .. "." .. SysTime()

            net.WriteString(randID)
            download = WebStream.WriteStream(randID, data, ply, function()
                ply.AdvDupe2.Downloading = false
                download = nil
            end, function()
                ply.AdvDupe2.Downloading = false
                download = nil
                net.Start("WebStream::AdvDupe2::FileReadyDownload")
                net.Send(ply)
            end)

            timer.Create("AdvDupe2::DownloadProgress", 0.25, 0, function()
                if not download then
                    timer.Remove("AdvDupe2::DownloadProgress")

                    return
                end

                AdvDupe2.UpdateProgressBar(ply, download:GetProgress() * 50)
            end)
        end

        function AdvDupe2.SendToClient(ply, data, autosave)
            if not IsValid(ply) then return end

            ply.AdvDupe2.Downloading = true
            AdvDupe2.InitProgressBar(ply, "Saving:")

            net.Start("AdvDupe2_ReceiveFile")
            net.WriteBool(autosave > 0)

            if WebStream and not WebStream.TempDisable and #data > 100000 and GetConVar("webstream_active_sv"):GetBool() and ply:GetInfoNum("webstream_active_cl", 0) == 1 then
                sendWebstream(data, ply)
            else
                sendNormal(data, ply)
            end

            net.Send(ply)
        end
    else
        local function parseData(data, autosave)
            AdvDupe2.RemoveProgressBar()

            if not data then
                AdvDupe2.Notify("File was not saved!", NOTIFY_ERROR, 5)

                return
            end

            local path

            if autosave then
                if LocalPlayer():GetInfo("advdupe2_auto_save_overwrite") ~= "0" then
                    path = AdvDupe2.GetFilename(AdvDupe2.AutoSavePath, true)
                else
                    path = AdvDupe2.GetFilename(AdvDupe2.AutoSavePath)
                end
            else
                path = AdvDupe2.GetFilename(AdvDupe2.SavePath)
            end

            local dupefile = file.Open(path, "wb", "DATA")

            if not dupefile then
                AdvDupe2.Notify("File was not saved!", NOTIFY_ERROR, 5)

                return
            end

            dupefile:Write(data)
            dupefile:Close()
            local errored = false

            if LocalPlayer():GetInfo("advdupe2_debug_openfile") == "1" then
                if not file.Exists(path, "DATA") then
                    AdvDupe2.Notify("File does not exist", NOTIFY_ERROR)

                    return
                end

                local readFile = file.Open(path, "rb", "DATA")

                if not readFile then
                    AdvDupe2.Notify("File could not be read", NOTIFY_ERROR)

                    return
                end

                local readData = readFile:Read(readFile:Size())
                readFile:Close()
                local success, dupe = AdvDupe2.Decode(readData)

                if success then
                    AdvDupe2.Notify("DEBUG CHECK: File successfully opens. No EOF errors.")
                else
                    AdvDupe2.Notify("DEBUG CHECK: " .. dupe, NOTIFY_ERROR)
                    errored = true
                end
            end

            local filename = string.StripExtension(string.GetFileFromFilename(path))

            if autosave then
                if IsValid(AdvDupe2.FileBrowser.AutoSaveNode) then
                    local add = true

                    for i = 1, #AdvDupe2.FileBrowser.AutoSaveNode.Files do
                        if filename == AdvDupe2.FileBrowser.AutoSaveNode.Files[i].Label:GetText() then
                            add = false
                            break
                        end
                    end

                    if add then
                        AdvDupe2.FileBrowser.AutoSaveNode:AddFile(filename)
                        AdvDupe2.FileBrowser.Browser.pnlCanvas:Sort(AdvDupe2.FileBrowser.AutoSaveNode)
                    end
                end
            else
                AdvDupe2.FileBrowser.Browser.pnlCanvas.ActionNode:AddFile(filename)
                AdvDupe2.FileBrowser.Browser.pnlCanvas:Sort(AdvDupe2.FileBrowser.Browser.pnlCanvas.ActionNode)
            end

            if not errored then
                AdvDupe2.Notify("File successfully saved!", NOTIFY_GENERIC, 5)
            end
        end

        local download
        local fileready = false

        net.Receive("WebStream::AdvDupe2::FileReadyDownload", function()
            fileready = true
        end)

        local function AdvDupe2_ReceiveFile()
            fileready = false
            local autosave = net.ReadBool()
            local id = net.ReadString()

            if string.sub(id, 1, 4) == "WS::" then
                download = WebStream.ReadStream(id, function(data)
                    parseData(data, autosave)

                    download = nil
                end)

                timer.Create("AdvDupe2::ReceiveProgress", 0.25, 0, function()
                    if not download then
                        timer.Remove("AdvDupe2::ReceiveProgress")

                        return
                    end

                    if fileready then
                        AdvDupe2.ProgressBar.Percent = 50 + download:GetProgress() * 50
                    end
                end)
            else
                net.ReadStream(nil, function(data)
                    parseData(data, autosave)
                end)
            end
        end

        net.Receive("AdvDupe2_ReceiveFile", AdvDupe2_ReceiveFile)
    end
end)