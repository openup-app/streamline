
const roomIdInput = document.getElementById('room-id');
const createButton = document.getElementById('create-button');
const joinButton = document.getElementById('join-button');

createButton.disabled = roomIdInput.value.length === 0;
joinButton.disabled = roomIdInput.value.length === 0;

async function init() {
    roomIdInput.addEventListener('input', (_) => {
        createButton.disabled = roomIdInput.value.length === 0;
        joinButton.disabled = roomIdInput.value.length === 0;
    });

    createButton.addEventListener('click', () => {
        const roomId = roomIdInput.value.trim().toLowerCase();
        window.location.href = `./room.html?id=${roomId}&host=true`;
    });

    joinButton.addEventListener('click', () => {
        const roomId = roomIdInput.value.trim().toLowerCase();
        window.location.href = `./room.html?id=${roomId}&host=false`;
    });
}

init();