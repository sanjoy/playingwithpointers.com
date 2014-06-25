function toggleNav() {
    var navigationBar = document.getElementById('navigation');
    var currentDisplay = window.getComputedStyle(navigationBar).getPropertyValue("display");

    if (currentDisplay === 'none') {
        navigationBar.style.display = 'block';
    } else {
        navigationBar.style.display = 'none';
    }
}
