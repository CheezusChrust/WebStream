WebStream = WebStream or {}
WebStream.StreamsWaitingForDownload = {}
WebStream.DownloadsReady = {}

local cvActive = CreateConVar("webstream_active_sv", "0", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "If enabled, dupes and P2Ms are sent via an external server to speed up large file transfers", 0, 1)
local cvDebug = CreateConVar("webstream_debug", "0", {FCVAR_ARCHIVE}, "Enable to see debug information printed to console", 0, 1)
local cvChunkSize = CreateConVar("webstream_chunksize", "1000", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "Data sent through webstreams will be split into chunks of this size, in kilobytes", 100, 10000)
local cvMaxRetries = CreateConVar("webstream_maxretries", "6", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "If a request fails, retry up to this many times", 0, 10)
local cvServer = CreateConVar("webstream_server", "", {FCVAR_REPLICATED, FCVAR_ARCHIVE}, "The webstream server address")

local realm = SERVER and "[SERVER]" or "[CLIENT]"
local realmColor = SERVER and Color(3, 169, 244) or Color(222, 169, 9)

local function debugPrint(dbg, ...)
    if (dbg and cvDebug:GetBool()) or not dbg then
        MsgC(realmColor, realm, Color(0, 200, 50), " [WebStream] ", Color(255, 255, 255), ..., "\n")
    end
end

if SERVER then
    util.AddNetworkString("WebStream::DownloadReady")
else
    CreateClientConVar("webstream_active_cl", "1", true, true, "If enabled, dupes and P2Ms are sent via an external server to speed up large file transfers", 0, 1)
end

local function disable(reason)
    debugPrint(false, "WebStream disabled: " .. reason)

    if SERVER then
        cvActive:SetBool(false)
    else
        GetConVar("webstream_active_cl"):SetBool(false)
    end
end

hook.Add("InitPostEntity", "WebStream::BeginStatusUpdates", function()
    timer.Create("WebStream::CheckStatus", 30, 0, function()
        local active

        if SERVER then
            active = cvActive:GetBool()
        else
            active = GetConVar("webstream_active_cl"):GetBool()
        end

        if not active then return end

        http.Fetch(cvServer:GetString(), function(body)
            if body ~= "OK" then
                disable("server returned non-OK value")
            end
        end, function(err)
            disable("server returned error: " .. err)
        end)
    end)
end)

local function SplitByChunk(text, chunkSize)
    local s = {}

    for i = 1, #text, chunkSize do
        s[#s + 1] = text:sub(i, i + chunkSize - 1)
    end

    return s
end

local function TransmitData(Stream)
    Stream.progress = Stream.progress + 1

    local chunkName = Stream.id .. SysTime() .. math.random()
    table.insert(Stream.chunkNames, chunkName)

    local chunkData = Stream.chunks[Stream.progress]
    debugPrint(true, "[" .. Stream.id .. "] Sending chunk " .. Stream.progress .. " of " .. #Stream.chunks .. ": " .. (#chunkData / 1000) .. " kB")

    HTTP({
        url = cvServer:GetString(),
        method = "POST",
        headers = {
            ["Content-Type"] = "application/octet-stream",
            ["WebStream-Name"] = chunkName
        },
        body = chunkData,
        timeout = 5,

        success = function(responseCode, body)
            if not Stream then return end

            if responseCode ~= 200 then
                debugPrint(false, "[" .. Stream.id .. "] Problem uploading chunk " .. Stream.progress .. " of " .. #Stream.chunks .. ": " .. body .. " (HTTP " .. responseCode .. ")")

                if Stream.onFailure then Stream.onFailure() end
            else
                if Stream.progress == #Stream.chunks then
                    debugPrint(true, "[" .. Stream.id .. "] Upload finished, uploaded " .. (#table.concat(Stream.chunks, "") / 1000) .. " kB")
                    if Stream.onSuccess then Stream.onSuccess() end

                    net.Start("WebStream::DownloadReady")
                    net.WriteString(Stream.id)
                    net.WriteTable(Stream.chunkNames)

                    if CLIENT then
                        net.SendToServer()
                    elseif not Stream.destination then
                        net.Broadcast()
                    else
                        net.Send(Stream.destination)
                    end
                else
                    TransmitData(Stream)
                end
            end
        end,

        failure = function(err)
            debugPrint(false, "[" .. Stream.id .. "] Problem uploading chunk " .. Stream.progress .. " of " .. #Stream.chunks .. ": " .. err .. ", retrying (attempt " .. Stream.retries .. ")")

            Stream.progress = Stream.progress - 1
            Stream.retries = Stream.retries + 1

            if Stream.retries <= cvMaxRetries:GetInt() then
                TransmitData(Stream)
            else
                if Stream.onFailure then Stream.onFailure() end
                debugPrint(false, "[" .. Stream.id .. "] Giving up after " .. Stream.retries .. " retries")
            end
        end
    })
end

--- Creates and starts a new WebStream
-- @param id A unique identifier for this stream
-- @param data The data to be sent
-- @param destination The player to send the data to, or nil to send to all players
-- @param onFailure A function to be called if the stream fails
-- @param onSuccess A function to be called if the stream succeeds
-- @return The stream object
function WebStream.WriteStream(id, data, destination, onFailure, onSuccess)
    debugPrint(true, "[" .. id .. "] WriteStream started (" .. (#data / 1000) .. " kB)")

    if not data or #data == 0 then
        error("[CLIENT] WebStream: WriteStream called with empty data")
    end

    if SERVER and destination and not destination:IsValid() then
        error("[SERVER] WebStream: WriteStream destination is invalid", 2)
    end

    local Stream = {}
    Stream.id = id
    Stream.destination = destination
    Stream.chunks = SplitByChunk(data, cvChunkSize:GetInt() * 1000)
    Stream.progress = 0 -- Chunk we're currently uploading
    Stream.chunkNames = {} -- Ordered table of chunk names that have been uploaded
    Stream.onFailure = onFailure
    Stream.onSuccess = onSuccess
    Stream.retries = 0

    function Stream:GetProgress()
        return self.progress / #self.chunks
    end

    function Stream:Remove()
        self = nil
    end

    TransmitData(Stream)

    return Stream
end

local function ReceiveData(Stream)
    Stream.progress = Stream.progress + 1

    debugPrint(true, "[" .. Stream.id .. "] Retrieving chunk " .. Stream.progress .. " of " .. #Stream.chunkNames)

    HTTP({
        url = cvServer:GetString(),
        method = "POST",
        headers = {
            ["WebStream-Name"] = Stream.chunkNames[Stream.progress]
        },
        timeout = 5,

        success = function(responseCode, body)
            if not Stream then return end

            if responseCode ~= 200 then
                debugPrint(false, "[" .. Stream.id .. "] Problem downloading chunk " .. Stream.progress .. " of " .. #Stream.chunkNames .. ": " .. body .. " (HTTP " .. responseCode .. ")")

                if Stream.onFailure then Stream.onFailure() end
            else
                table.insert(Stream.data, body)
                if Stream.progress == #Stream.chunkNames then
                    local data = table.concat(Stream.data, "")
                    debugPrint(true, "[" .. Stream.id .. "] Download finished, downloaded " .. (#data / 1000) .. " kB")
                    Stream.callback(data)
                    WebStream.DownloadsReady[Stream.id] = nil
                    WebStream.StreamsWaitingForDownload[Stream.id] = nil
                else
                    ReceiveData(Stream)
                end
            end
        end,

        failure = function(err)
            debugPrint(false, "[" .. Stream.id .. "] Problem downloading chunk " .. Stream.progress .. " of " .. #Stream.chunkNames .. ": " .. err .. ", retrying (attempt " .. Stream.retries .. ")")

            Stream.progress = Stream.progress - 1
            Stream.retries = Stream.retries + 1

            if Stream.retries <= cvMaxRetries:GetInt() then
                ReceiveData(Stream)
            else
                if Stream.onFailure then Stream.onFailure() end
                debugPrint(false, "[" .. Stream.id .. "] Giving up after " .. Stream.retries .. " retries")
            end
        end
    })
end

--- Reads a WebStream if one with the given ID is ready
-- @param id The ID of the stream to read
-- @param callback A function to be called when the stream has finished downloading, with the data as the first argument
-- @param onFailure A function to be called if the stream fails
-- @return The stream object
function WebStream.ReadStream(id, callback, onFailure)
    debugPrint(true, "[" .. id .. "] ReadStream started")
    local Stream = {}
    Stream.id = id
    Stream.callback = callback
    Stream.onFailure = onFailure
    Stream.progress = 0
    Stream.chunkNames = {}
    Stream.data = {}
    Stream.retries = 0

    function Stream:GetProgress()
        return self.progress / #self.chunkNames
    end

    function Stream:Remove()
        WebStream.StreamsWaitingForDownload[self.id] = nil
        self = nil
    end

    if WebStream.DownloadsReady[id] then
        Stream.chunkNames = WebStream.DownloadsReady[id]
        ReceiveData(Stream)
    else
        WebStream.StreamsWaitingForDownload[id] = Stream
    end

    return Stream
end

net.Receive("WebStream::DownloadReady", function()
    local id = net.ReadString()
    local chunkNames = net.ReadTable()

    debugPrint(true, "[" .. id .. "] Download is ready, " .. #chunkNames .. " chunk(s)")

    if not WebStream.StreamsWaitingForDownload[id] then
        WebStream.DownloadsReady[id] = chunkNames
    else
        WebStream.StreamsWaitingForDownload[id].chunkNames = chunkNames
        ReceiveData(WebStream.StreamsWaitingForDownload[id])
    end
end)