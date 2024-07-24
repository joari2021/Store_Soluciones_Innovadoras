// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails";
import "controllers";

// app/javascript/application.js
import "bootstrap";

let loadMoreBtn1 = document.querySelector("#load-more-1");
let currentItem1 = 4;

loadMoreBtn1.onclick = () => {
  let boxes = [...document.querySelectorAll(".box-container-1 .box-1")];
  // Asegúrate de que el índice no sea mayor que el número de elementos disponibles
  let nextItems = Math.min(currentItem1 + 4, boxes.length);

  for (let i = currentItem1; i < nextItems; i++) {
    boxes[i].style.display = "inline-block";
  }

  currentItem1 = nextItems;

  if (currentItem1 >= boxes.length) {
    loadMoreBtn1.style.display = "none";
  }
};
