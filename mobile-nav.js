var originalNavClasses;

function toggleNav() {
    var navigationBar = document.getElementById('navigation');
    var content = document.getElementById('content');

    if (navigationBar.style.display === 'none') {
        navigationBar.style.display = 'block';
    } else {
        navigationBar.style.display = 'none';
    }
}
