-- Alacena schema v1. Each statement block has its own delimiter comment.
-- statement
CREATE TABLE Sucursal (
 id INTEGER PRIMARY KEY,
 name TEXT NOT NULL COLLATE NOCASE UNIQUE CHECK(length(trim(name)) BETWEEN 1 AND 100),
 address TEXT NOT NULL CHECK(length(trim(address)) > 0),
 latitude REAL NOT NULL CHECK(latitude BETWEEN -90 AND 90),
 longitude REAL NOT NULL CHECK(longitude BETWEEN -180 AND 180)
);
-- statement
CREATE TABLE Tienda (
 id INTEGER PRIMARY KEY,
 name TEXT NOT NULL COLLATE NOCASE UNIQUE CHECK(length(trim(name)) BETWEEN 1 AND 100),
 address TEXT NOT NULL DEFAULT ''
);
-- statement
CREATE TABLE Categoria (
 id INTEGER PRIMARY KEY,
 name TEXT NOT NULL COLLATE NOCASE UNIQUE CHECK(length(trim(name)) BETWEEN 1 AND 100)
);
-- statement
CREATE TABLE Producto (
 id INTEGER PRIMARY KEY,
 category_id INTEGER NOT NULL REFERENCES Categoria(id) ON DELETE RESTRICT,
 name TEXT NOT NULL COLLATE NOCASE UNIQUE CHECK(length(trim(name)) BETWEEN 1 AND 120),
 unit TEXT NOT NULL DEFAULT 'pieza' CHECK(length(trim(unit)) > 0),
 image_path TEXT,
 image_asset TEXT NOT NULL DEFAULT 'assets/products/grocery.svg',
 ultima_tienda_id INTEGER REFERENCES Tienda(id) ON DELETE RESTRICT
);
-- statement
CREATE TABLE ProductoSucursal (
 id INTEGER PRIMARY KEY,
 branch_id INTEGER NOT NULL REFERENCES Sucursal(id) ON DELETE RESTRICT,
 product_id INTEGER NOT NULL REFERENCES Producto(id) ON DELETE RESTRICT,
 minimum_stock INTEGER NOT NULL DEFAULT 2 CHECK(typeof(minimum_stock)='integer' AND minimum_stock>=0),
 warning_days INTEGER NOT NULL DEFAULT 7 CHECK(typeof(warning_days)='integer' AND warning_days BETWEEN 0 AND 365),
 reminders INTEGER NOT NULL DEFAULT 1 CHECK(reminders IN (0,1)),
 ultima_tienda_id INTEGER REFERENCES Tienda(id) ON DELETE RESTRICT,
 UNIQUE(branch_id, product_id), UNIQUE(id,branch_id), UNIQUE(id,branch_id,product_id)
);
-- statement
CREATE TABLE OrdenCompra (
 id INTEGER PRIMARY KEY,
 branch_id INTEGER NOT NULL REFERENCES Sucursal(id) ON DELETE RESTRICT,
 supplier_id INTEGER NOT NULL REFERENCES Tienda(id) ON DELETE RESTRICT,
 status TEXT NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','ordered','partial','received','cancelled')),
 branch_name TEXT NOT NULL,
 supplier_name TEXT NOT NULL,
 created_at TEXT NOT NULL,
 UNIQUE(id,branch_id), UNIQUE(id,branch_id,supplier_id)
);
-- statement
CREATE TABLE DetalleOrdenCompra (
 id INTEGER PRIMARY KEY,
 order_id INTEGER NOT NULL,
 branch_id INTEGER NOT NULL,
 branch_product_id INTEGER NOT NULL,
 quantity INTEGER NOT NULL CHECK(typeof(quantity)='integer' AND quantity>0),
 unit_cost INTEGER NOT NULL CHECK(typeof(unit_cost)='integer' AND unit_cost>=0),
 product_name TEXT NOT NULL,
 unit TEXT NOT NULL,
 FOREIGN KEY(order_id,branch_id) REFERENCES OrdenCompra(id,branch_id) ON DELETE CASCADE,
 FOREIGN KEY(branch_product_id,branch_id) REFERENCES ProductoSucursal(id,branch_id) ON DELETE RESTRICT,
 UNIQUE(order_id,branch_product_id), UNIQUE(id,order_id,branch_id,branch_product_id)
);
-- statement
CREATE TABLE Recepcion (
 id INTEGER PRIMARY KEY,
 order_id INTEGER NOT NULL,
 branch_id INTEGER NOT NULL,
 operation_id TEXT NOT NULL UNIQUE CHECK(length(operation_id)>0),
 payload TEXT NOT NULL,
 created_at TEXT NOT NULL,
 FOREIGN KEY(order_id,branch_id) REFERENCES OrdenCompra(id,branch_id) ON DELETE RESTRICT,
 UNIQUE(id,order_id,branch_id)
);
-- statement
CREATE TABLE Historial_Compras (
 id INTEGER PRIMARY KEY,
 receipt_id INTEGER NOT NULL,
 order_id INTEGER NOT NULL,
 order_line_id INTEGER NOT NULL,
 branch_id INTEGER NOT NULL,
 branch_product_id INTEGER NOT NULL,
 product_id INTEGER NOT NULL,
 supplier_id INTEGER NOT NULL,
 quantity INTEGER NOT NULL CHECK(typeof(quantity)='integer' AND quantity>0),
 unit_cost INTEGER NOT NULL CHECK(typeof(unit_cost)='integer' AND unit_cost>=0),
 product_name TEXT NOT NULL,
 unit TEXT NOT NULL,
 branch_name TEXT NOT NULL,
 supplier_name TEXT NOT NULL,
 created_at TEXT NOT NULL,
 FOREIGN KEY(receipt_id,order_id,branch_id) REFERENCES Recepcion(id,order_id,branch_id) ON DELETE RESTRICT,
 FOREIGN KEY(order_line_id,order_id,branch_id,branch_product_id) REFERENCES DetalleOrdenCompra(id,order_id,branch_id,branch_product_id) ON DELETE RESTRICT,
 FOREIGN KEY(branch_product_id,branch_id,product_id) REFERENCES ProductoSucursal(id,branch_id,product_id) ON DELETE RESTRICT,
 FOREIGN KEY(order_id,branch_id,supplier_id) REFERENCES OrdenCompra(id,branch_id,supplier_id) ON DELETE RESTRICT,
 UNIQUE(id,branch_product_id,branch_id,quantity)
);
-- statement
CREATE TABLE Lote (
 id INTEGER PRIMARY KEY,
 branch_id INTEGER NOT NULL,
 branch_product_id INTEGER NOT NULL,
 purchase_id INTEGER NOT NULL UNIQUE,
 initial_quantity INTEGER NOT NULL CHECK(typeof(initial_quantity)='integer' AND initial_quantity>0),
 cantidad INTEGER NOT NULL CHECK(typeof(cantidad)='integer' AND cantidad BETWEEN 0 AND initial_quantity),
 expiry_date TEXT CHECK(expiry_date IS NULL OR (length(expiry_date)=10 AND expiry_date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]')),
 fecha_alarma TEXT,
 FOREIGN KEY(purchase_id,branch_product_id,branch_id,initial_quantity) REFERENCES Historial_Compras(id,branch_product_id,branch_id,quantity) ON DELETE RESTRICT,
 UNIQUE(id,branch_product_id,branch_id)
);
-- statement
CREATE TABLE Carrito_Item (
 id INTEGER PRIMARY KEY,
 branch_id INTEGER NOT NULL,
 branch_product_id INTEGER NOT NULL,
 quantity INTEGER NOT NULL CHECK(typeof(quantity)='integer' AND quantity>0),
 FOREIGN KEY(branch_product_id,branch_id) REFERENCES ProductoSucursal(id,branch_id) ON DELETE RESTRICT,
 UNIQUE(branch_id,branch_product_id)
);
-- statement
CREATE TABLE Movimiento_Inventario (
 id INTEGER PRIMARY KEY,
 branch_id INTEGER NOT NULL,
 branch_product_id INTEGER NOT NULL,
 lot_id INTEGER NOT NULL,
 kind TEXT NOT NULL CHECK(kind IN ('receipt','consume','discard')),
 quantity INTEGER NOT NULL CHECK(typeof(quantity)='integer' AND quantity>0),
 reason TEXT NOT NULL DEFAULT '',
 created_at TEXT NOT NULL,
 FOREIGN KEY(lot_id,branch_product_id,branch_id) REFERENCES Lote(id,branch_product_id,branch_id) ON DELETE RESTRICT
);
-- statement
CREATE TABLE EventoOrden (
 id INTEGER PRIMARY KEY,
 branch_id INTEGER NOT NULL,
 order_id INTEGER NOT NULL,
 kind TEXT NOT NULL CHECK(kind IN ('draft','edited','ordered','partial','received','cancelled')),
 note TEXT NOT NULL DEFAULT '',
 created_at TEXT NOT NULL,
 FOREIGN KEY(order_id,branch_id) REFERENCES OrdenCompra(id,branch_id) ON DELETE CASCADE
);
-- statement
CREATE TABLE ReporteExportado (
 id TEXT PRIMARY KEY,
 branch_id INTEGER REFERENCES Sucursal(id) ON DELETE RESTRICT,
 scope_name TEXT NOT NULL,
 period TEXT NOT NULL,
 starts_at TEXT NOT NULL,
 ends_at TEXT NOT NULL,
 generated_at TEXT NOT NULL,
 timezone TEXT NOT NULL,
 file_path TEXT NOT NULL UNIQUE
);
-- statement
CREATE TABLE Configuracion (key TEXT PRIMARY KEY,value TEXT NOT NULL);
-- statement
INSERT INTO Configuracion(key,value) VALUES ('reminder_hour','9'),('reminder_minute','0');
-- statement
CREATE TRIGGER ultima_tienda_compra AFTER INSERT ON Historial_Compras BEGIN
 UPDATE Producto SET ultima_tienda_id=NEW.supplier_id WHERE id=NEW.product_id;
 UPDATE ProductoSucursal SET ultima_tienda_id=NEW.supplier_id WHERE id=NEW.branch_product_id AND branch_id=NEW.branch_id;
END;
-- statement
CREATE TRIGGER compra_inmutable_update BEFORE UPDATE ON Historial_Compras BEGIN SELECT RAISE(ABORT,'El historial de compras es inmutable'); END;
-- statement
CREATE TRIGGER compra_inmutable_delete BEFORE DELETE ON Historial_Compras BEGIN SELECT RAISE(ABORT,'El historial de compras es inmutable'); END;
-- statement
CREATE TRIGGER movimiento_inmutable_update BEFORE UPDATE ON Movimiento_Inventario BEGIN SELECT RAISE(ABORT,'El movimiento es inmutable'); END;
-- statement
CREATE TRIGGER movimiento_inmutable_delete BEFORE DELETE ON Movimiento_Inventario BEGIN SELECT RAISE(ABORT,'El movimiento es inmutable'); END;
-- statement
CREATE INDEX lotes_fefo ON Lote(branch_id,branch_product_id,expiry_date,id);
-- statement
CREATE INDEX compras_periodo ON Historial_Compras(branch_id,created_at);
-- statement
CREATE INDEX movimientos_periodo ON Movimiento_Inventario(branch_id,created_at);
-- statement
CREATE INDEX eventos_periodo ON EventoOrden(branch_id,created_at);
-- statement
CREATE INDEX compras_linea ON Historial_Compras(order_line_id);
