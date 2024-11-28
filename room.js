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

            parameters.encodings[0].maxBitrate = 140000000;
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
                return `a=fmtp:${vp9PayloadType} profile-id=2;max-fr=60;max-fs=8294400;level-asymmetry-allowed=1`;
            }

            // Add bitrate settings for VP9
            if (line.startsWith(`a=rtpmap:${vp9PayloadType}`)) {
                return `${line}\r\na=fmtp:${vp9PayloadType} x-google-min-bitrate=140000;x-google-max-bitrate=140000;x-google-start-bitrate=140000`;
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
        .map((line) => {
            // Ensure AV1 has the highest priority in m=video
            if (line.startsWith("m=video")) {
                const parts = line.split(" ");
                const codecIndices = parts.slice(3); // Codec payload types
                const prioritized = [av1PayloadType, ...codecIndices.filter((p) => p !== av1PayloadType)];
                return `${parts.slice(0, 3).join(" ")} ${prioritized.join(" ")}`;
            }

            // Modify AV1 fmtp line to enforce high-resolution settings
            if (line.startsWith(`a=fmtp:${av1PayloadType}`)) {
                return `a=fmtp:${av1PayloadType} level-idx=13;profile=1;tier=0;max-fr=60;max-fs=829440;max-br=140000;`;
            }

            // Add bitrate settings for AV1
            if (line.startsWith(`a=rtpmap:${av1PayloadType}`)) {
                return `${line}\r\na=fmtp:${av1PayloadType} x-google-min-bitrate=140000;x-google-max-bitrate=140000;x-google-start-bitrate=140000`;
            }

            return line;
        });

    // Return the modified SDP
    return updatedSDP.join("\r\n");
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