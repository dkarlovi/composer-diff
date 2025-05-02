<?php

require __DIR__.'/../vendor/autoload.php';

use App\Comparator;
use App\Twig;

$isInsideWasm = PHP_SAPI === 'embed';
$old = null;
$new = null;
if ($isInsideWasm) {
    // inside WASM
    $old = file_get_contents($argv[1]);
    $new = file_get_contents($argv[2]);
} else if ('POST' === $_SERVER['REQUEST_METHOD']) {
    // inside web server
    $old = $_POST['old'];
    $new = $_POST['new'];
}

$result = null;
if ($old !== null && $new !== null) {
    $result = (new Comparator())->compare($old, $new);
} 

echo (new Twig())->render('index.html.twig', [
    'wasm' => !$isInsideWasm, 
    'result' => $result,
]);
