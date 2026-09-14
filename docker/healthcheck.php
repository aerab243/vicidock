<?php
// VICIdock — healthcheck fonctionnel : connexion DB réelle + extensions PHP.
// Répond 200 si sain, 503 sinon. N'expose aucun secret.
header('Content-Type: application/json');

$checks = [];
$healthy = true;

$db = @new mysqli('localhost', 'cron', (string) getenv('MYSQL_CRON_PASSWORD'), 'asterisk');
if ($db->connect_error) {
    $checks['mysql'] = 'FAIL';
    $healthy = false;
} else {
    $result = $db->query('SELECT COUNT(*) AS cnt FROM vicidial_campaigns');
    if ($result && ($row = $result->fetch_assoc())) {
        $checks['mysql'] = 'OK';
    } else {
        $checks['mysql'] = 'FAIL';
        $healthy = false;
    }
    $db->close();
}

foreach (['mysqli', 'gd', 'mbstring'] as $ext) {
    if (!extension_loaded($ext)) {
        $checks['php_' . $ext] = 'FAIL';
        $healthy = false;
    } else {
        $checks['php_' . $ext] = 'OK';
    }
}

http_response_code($healthy ? 200 : 503);
echo json_encode(['status' => $healthy ? 'healthy' : 'unhealthy', 'checks' => $checks]);
