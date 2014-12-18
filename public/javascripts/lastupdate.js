function updateTime() {
    var d = new Date();
    document.getElementById("LastUpdate").firstChild.nodeValue =
    d.toTimeString().substring(0, 8) + " " + d.toLocaleDateString();
}
