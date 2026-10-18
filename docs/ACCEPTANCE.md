# Verificación y presentación

Fecha de revisión: 17 de octubre de 2026. Las pruebas usan datos aislados; el primer inicio de la aplicación permanece vacío.

## Evidencia automatizada

| Comprobación | Resultado |
|---|---|
| Análisis estático Flutter | Sin incidencias |
| Pruebas locales | 25 aprobadas: reglas, SQLite, reportes, recordatorios y widgets |
| Integración Android | Aprobada en emulador arm64 API 36 |
| APK debug | Compilación completada |
| PDF | Vacío, corto y extenso generados; inspección de 47 páginas del reporte extenso, encabezados, totales y numeración |
| Vista previa PDF Android | Renderizado nativo de primera página y apertura de PdfPreview comprobados |
| Mapa Android | Teselas reales, atribución visible, dos marcadores, panel y apertura de la tienda; capturas revisadas |
| iOS | Configuración preparada; sin compilación/ejecución por falta de Xcode completo |

La integración nativa comprueba creación y reapertura de SQLite, entrega parcial y confirmación repetida, FEFO, aislamiento de sucursales, cancelación de pendientes, archivo PDF guardado, notificación programada y dos marcadores en el mapa con apertura de la tienda seleccionada. La programación de una notificación no demuestra su entrega real después de reiniciar o bajo restricciones de batería.

## Casos cubiertos

| Caso | Evidencia |
|---|---|
| Mismo producto con stock, carrito y umbrales independientes en dos tiendas | SQLite y recorrido Android |
| Cambio de sucursal reinicia navegación y cambia contador | Prueba de widgets |
| Consumo de varios lotes por FEFO | SQLite y Android |
| Consumo excesivo no cambia ningún lote | SQLite |
| Vencidos bloquean solo la sucursal afectada | SQLite |
| Entrega parcial actualiza stock y costos reales | SQLite y Android |
| Repetir recepción no duplica; reutilizar ID con otro contenido falla | SQLite y Android |
| Cancelar conserva lo recibido | SQLite y Android |
| Proveedores globales y últimos proveedores por tienda | SQLite |
| Historial inmutable y eliminación de maestros referenciados restringida | Restricciones SQLite |
| Cinco productos generan cinco puntos y cinco entradas en modal completo | Widgets |
| Día desde aviso pendiente abre al montar la app | Widgets; no equivale a toque del aviso del sistema |
| Sin datos y pantalla estrecha con texto aumentado | Widgets y revisión de capturas |
| Los seis períodos incluyen inicio y excluyen fin | Reglas de dominio |
| Fin de mes, cambio de año y año bisiesto | Reglas de dominio |
| Pedido anterior con recepción o consumo en período aparece como contexto | Reportes con base real |
| Totales por alcance, períodos vacíos y datos congelados | Reportes |
| Alarmas deduplicadas entre lotes/tiendas y límite de 60 | Recordatorios |
| PDF largo conserva tablas y referencias | Generación y revisión de páginas renderizadas |

## Guion de presentación

1. Crear **Centro** y **Jardines**, categoría **Lácteos**, artículo **Leche** y proveedores **Mercado A** y **Mercado B**.
2. Asignar Leche a ambas tiendas: ambas deben iniciar agotadas.
3. En Centro agregar 8 unidades al carrito; guardar y enviar un pedido a Mercado A. Mostrar que enviar no crea stock.
4. Recibir 3 unidades con caducidad cercana y 2 con una fecha posterior. Mostrar estado parcial, dos lotes, cinco unidades y costo recibido real.
5. Consumir 4: el primer lote debe quedar en cero y el segundo en una unidad. Jardines debe seguir en cero.
6. Cancelar las 3 unidades pendientes. El lote restante y sus compras deben conservarse.
7. Comprar nuevamente a Mercado B. Mostrar ambos proveedores históricos y la última compra actualizada.
8. Registrar una recepción con fecha de ayer. Intentar consumir y mostrar el bloqueo. Descartar el vencido con motivo; continuar consumo de lo válido.
9. Crear otros cuatro artículos con alertas hoy. Abrir Calendario, mostrar los cinco puntos y abrir el modal del día completo con sus imágenes.
10. Volver al mapa, seleccionar Jardines y abrirla; comprobar su stock independiente. Reabrir la app y verificar coordenadas persistidas.
11. Generar PDF global y de Centro; mostrar las seis opciones, gasto recibido separado del solicitado, lotes y movimientos. Compartir a Archivos o a una aplicación elegida para la presentación.
12. Mostrar GitHub, esquema SQL, Slivers y los widgets adicionales SearchAnchor y DraggableScrollableSheet.

## Validación pendiente en dispositivos

Estas comprobaciones requieren interacción con el sistema o hardware y deben repetirse en los dos sistemas antes de afirmar validación completa:

- **iOS:** instalar/configurar Xcode y firma; compilar, ejecutar SQLite, mapas, cámara/galería, PDF y permisos en simulador/iPhone.
- **Notificaciones:** conceder y denegar permiso; establecer una hora cercana, esperar un aviso real y tocarlo con la app abierta, en segundo plano y terminada. Confirmar que el día abre con tiendas y productos correctos. Revisar reinicio Android y cambio de zona/fecha.
- **Compartir e imprimir:** abrir la hoja del sistema, guardar una copia externa y compararla con la vista previa; imprimir en una impresora si se dispone de ella. Abrir la hoja no significa haber entregado un archivo a otra persona.
- **Fotografías:** escoger y tomar una foto, cancelar el selector, denegar permisos, reiniciar y verificar que la copia local permanece.
- **Mapa:** mover/guardar un punto y probar sin conexión; direcciones y selección deben permanecer utilizables. Comprobar zoom, atribución y ausencia de carga masiva de teselas.
- **Accesibilidad y tamaños:** recorrer formularios largos con teclado, textos grandes, modo horizontal y VoiceOver/TalkBack.

## Límites de esta entrega

Sin sincronización entre dispositivos, ventas, traspasos, seguimiento GPS o restauración de respaldos. Los datos locales se pueden perder al desinstalar. La configuración release conserva firma de desarrollo; esta entrega está orientada a la práctica y no a publicar en las tiendas de aplicaciones.
