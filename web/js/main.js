import { createOptions } from "./createOptions.js";
import { fetchNui } from "./fetchNui.js";

const body = document.body;
const optionsWrapper = document.getElementById("options-wrapper");

function createCloseButton() {
  const closeOption = document.createElement("div");
  closeOption.innerHTML = `<i class="fa-fw fa-solid fa-xmark option-icon"></i><p class="option-label">Fermer le menu</p>`;
  closeOption.className = "option-container";

  closeOption.addEventListener("click", function () {
    this.style.pointerEvents = "none";
    fetchNui("select", ["builtin", "close"]);
    setTimeout(() => (this.style.pointerEvents = "auto"), 100);
  });

  optionsWrapper.appendChild(closeOption);
}

window.addEventListener("message", (event) => {
  switch (event.data.event) {
    case "visible": {
      optionsWrapper.innerHTML = "";
      body.style.visibility = event.data.state ? "visible" : "hidden";
      return;
    }

    case "leftTarget": {
      optionsWrapper.innerHTML = "";
      return;
    }

    case "setTarget": {
      optionsWrapper.innerHTML = "";

      if (event.data.options) {
        for (const type in event.data.options) {
          event.data.options[type].forEach((data, id) => {
            createOptions(type, data, id + 1);
          });
        }
      }

      if (event.data.zones) {
        for (let i = 0; i < event.data.zones.length; i++) {
          event.data.zones[i].forEach((data, id) => {
            createOptions("zones", data, id + 1, i + 1);
          });
        }
      }

      createCloseButton();

      if (event.data.cursorX !== undefined && event.data.cursorY !== undefined) {
        const screenWidth = window.innerWidth;
        const screenHeight = window.innerHeight;

        const cursorPixelX = event.data.cursorX * screenWidth;
        const cursorPixelY = event.data.cursorY * screenHeight;

        const mouseEvent = new MouseEvent('mousemove', {
          clientX: cursorPixelX,
          clientY: cursorPixelY,
          bubbles: true
        });
        document.dispatchEvent(mouseEvent);

        requestAnimationFrame(() => {
          const menuWidth = optionsWrapper.offsetWidth;
          const menuHeight = optionsWrapper.offsetHeight;

          let posX = cursorPixelX + 20;
          let posY = cursorPixelY;

          if (posX + menuWidth > screenWidth) {
            posX = cursorPixelX - menuWidth - 20;
          }

          if (posX < 0) {
            posX = 10;
          }

          if (posY + menuHeight > screenHeight) {
            posY = screenHeight - menuHeight - 10;
          }

          if (posY < 0) {
            posY = 10;
          }

          optionsWrapper.style.left = `${posX}px`;
          optionsWrapper.style.top = `${posY}px`;
        });
      }
    }
  }
});
