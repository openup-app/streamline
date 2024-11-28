let roomTitle = document.getElementById('room-title');
const localVideo = document.getElementById('local-video');
const remoteVideo = document.getElementById('remote-video');
const muteButton = document.getElementById('mute-button');
const fullscreenButton = document.getElementById('fullscreen-button');
const videoSelect = document.querySelector('select#videoSource');
const infoText = document.getElementById('info');
const errorText = document.getElementById('error');
let globalCall;

function toggleFullScreen() {
    if (document.fullscreenElement) {
        document.exitFullscreen();
    } else {
        document.documentElement.requestFullscreen();
    }
}

async function updateCameraList() {
    const deviceInfos = await navigator.mediaDevices.enumerateDevices();
    console.log('Available input and output devices:', deviceInfos);
    const videoSelect = document.querySelector('select#videoSource');

    for (const deviceInfo of deviceInfos) {
        const option = document.createElement('option');
        option.value = deviceInfo.deviceId;
        if (deviceInfo.kind === 'videoinput') {
            option.text = deviceInfo.label || `Camera ${videoSelect.length + 1}`;
            videoSelect.appendChild(option);
        }
    }
}

function onCameraOptionChanged() {
    const videoSelect = document.querySelector('select#videoSource');
    const localVideo = document.getElementById('local-video');
    const localStream = localVideo.srcObject;
    setCamera(localStream, globalCall, videoSelect.value);
}

async function setCamera(localStream, call, deviceId) {
    const newStream = await navigator.mediaDevices.getUserMedia({
        video: { deviceId: deviceId },
        audio: true
    });

    const videoTrack = newStream.getVideoTracks()[0];
    const currentVideoTrack = localStream.getVideoTracks()[0];

    localStream.removeTrack(currentVideoTrack);
    localStream.addTrack(videoTrack);
    localVideo.srcObject = localStream;
    localVideo.muted = true;
    const videoTracks = call.peerConnection.getSenders().filter((e) => e.track.kind === "video");
    videoTracks[0].replaceTrack(videoTrack);

}

function setCallQuality(call) {
    call.peerConnection.getSenders().forEach(async sender => {
        if (sender.track.kind === 'video') {
            const parameters = sender.getParameters();

            if (!parameters.encodings) {
                parameters.encodings = [{}];
            }

            parameters.encodings[0].maxBitrate = 30000000;
            parameters.encodings[0].maxFramerate = 60;
            parameters.encodings[0].scaleResolutionDownBy = 1.0;

            try {
                await sender.setParameters(parameters);
                console.log("Video bitrate and quality parameters set successfully");
            } catch (e) {
                console.error(`Error setting bitrate: ${e}`);
            }
        }
    });
}

function useVp9SdpTransform(sdp) {
    // Split the SDP into lines for processing
    const sdpLines = sdp.split('\r\n');

    // Extract the VP9 payload type
    let vp9PayloadType = null;
    for (const line of sdpLines) {
        if (line.startsWith("a=rtpmap:") && line.includes("VP9/90000")) {
            // e.g., "a=rtpmap:98 VP9/90000" -> 98
            vp9PayloadType = line.split(" ")[0].split(":")[1];
            break;
        }
    }

    // If VP9 isn't present in the SDP, return the original SDP
    if (!vp9PayloadType) {
        console.warn("VP9 codec not found in SDP");
        return sdp;
    }

    const updatedSDP = sdpLines
        .map((line) => {
            // Ensure VP9 has the highest priority in m=video
            if (line.startsWith("m=video")) {
                const parts = line.split(" ");
                const codecIndices = parts.slice(3); // Codec payload types
                const prioritized = [vp9PayloadType, ...codecIndices.filter((p) => p !== vp9PayloadType)];
                return `${parts.slice(0, 3).join(" ")} ${prioritized.join(" ")}`;
            }

            // Modify VP9 fmtp line to enforce 4K settings
            if (line.startsWith(`a=fmtp:${vp9PayloadType}`)) {
                // Add/modify VP9 settings for max resolution, frame rate, and bitrate
                return `a=fmtp:${vp9PayloadType} profile-id=0;max-fr=60;max-fs=921600;level-asymmetry-allowed=1`;
            }

            // Add bitrate settings for VP9
            if (line.startsWith(`a=rtpmap:${vp9PayloadType}`)) {
                return `${line}\r\na=fmtp:${vp9PayloadType} x-google-min-bitrate=40000;x-google-max-bitrate=40000;x-google-start-bitrate=40000`;
            }

            return line;
        });

    // Return the modified SDP
    return updatedSDP.join("\r\n");
}


function useAv1SdpTransform(sdp) {
    // Split the SDP into lines for processing
    const sdpLines = sdp.split('\r\n');

    // Extract the AV1 payload type which is dynamic
    // see https://en.wikipedia.org/wiki/RTP_payload_formats
    let av1PayloadType = null;
    for (const line of sdpLines) {
        if (line.startsWith("a=rtpmap:") && line.includes("AV1/90000")) {
            // e.g., "a=rtpmap:45 AV1/90000" -> 45
            av1PayloadType = line.split(" ")[0].split(":")[1];
            break;
        }
    }

    // If AV1 isn't present in the SDP, return the original SDP
    if (!av1PayloadType) {
        console.warn("AV1 codec not found in SDP");
        return sdp;
    }

    const updatedSDP = sdpLines
        .filter((line) => {
            // Remove lines that set retransmission or recovery options for non-AV1 codecs
            if (line.startsWith("a=rtcp-fb:") && !line.includes(`a=rtcp-fb:${av1PayloadType}`)) {
                return false;
            }
            return true;
        })
        .map((line) => {
            // Ensure AV1 has the highest priority in m=video
            if (line.startsWith("m=video")) {
                const parts = line.split(" ");
                const codecIndices = parts.slice(3); // Codec payload types
                const prioritized = [av1PayloadType, ...codecIndices.filter((p) => p !== av1PayloadType)];
                return `${parts.slice(0, 3).join(" ")} ${prioritized.join(" ")}`;
            }
            return line;
        });

    // Return the modified SDP
    const out = updatedSDP.join("\r\n");
    return out;
}

async function init() {
    let isMuted = false;

    videoSelect.onchange = onCameraOptionChanged;

    const urlParams = new URLSearchParams(window.location.search);
    const roomName = urlParams.get('id');
    let isHost = urlParams.get('host') === "true";

    if (!roomName) {
        roomTitle.innerHTML = "Missing Room Name";
        return;
    } else {
        roomTitle.innerHTML = `${roomName} (${isHost ? 'Host' : 'Client'})`;
    }

    try {
        const stream = await navigator.mediaDevices.getUserMedia({
            video: {
                facingMode: "environment"
            },
            audio: {
                echoCancellation: true,
                noiseSuppression: true,
                autoGainControl: true,
            }
        });

        localVideo.srcObject = stream;
        // const stream = localVideo.captureStream();
        const myId = `com_openup_${roomName}_${isHost ? 'host' : 'client'}`;
        const peer = new window.Peer(myId);

        peer.on('open', id => {
            console.log(`Open with id ${id}`);

            peer.on('call', call => {
                globalCall = call;
                const options = { sdpTransform: useVp9SdpTransform };
                call.answer(stream, options);
                call.on('stream', remoteStream => {
                    infoText.innerHTML = "Connected";
                    remoteVideo.srcObject = remoteStream;
                });
                call.on('close', () => {
                    infoText.innerHTML = "Waiting For Connection";
                });

                setCallQuality(call);
            });

            if (!isHost) {
                const partnerId = `com_openup_${roomName}_${isHost ? 'client' : 'host'}`;
                const options = { sdpTransform: useVp9SdpTransform };
                const call = peer.call(partnerId, stream, options);
                globalCall = call;
                call.on('stream', remoteStream => {
                    infoText.innerHTML = "Connected";
                    remoteVideo.srcObject = remoteStream;
                });
                setCallQuality(call);
            }
        });

        peer.on('error', err => {
            console.error('PeerJS error:', err);
            errorText.innerHTML = `PeerJS error: ${err}`;
        });

        muteButton.addEventListener('click', () => {
            if (stream) {
                stream.getAudioTracks().forEach(track => {
                    track.enabled = !track.enabled;
                });
                isMuted = !isMuted;
                muteButton.textContent = isMuted ? 'Unmute' : 'Mute';
            }
        });

        fullscreenButton.addEventListener('click', () => {
            toggleFullScreen();
        })

    } catch (e) {
        console.log(`Error getting local media: ${e}`);
        errorText.innerHTML = `Error getting local media: ${e}`;

    }
}

init();
updateCameraList();