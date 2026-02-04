CREATE TABLE raw_medical_sales (
    "Invoice" VARCHAR(50),         
    "StockCode" VARCHAR(50),      
    "Description" TEXT,
    "Quantity" INTEGER,
    "InvoiceDate" TIMESTAMP,       
    "Price" NUMERIC,
    "Customer ID" VARCHAR(50),    
    "Country" VARCHAR(50),
    "Product_Category" VARCHAR(100),
    "Product_Name" VARCHAR(100)
);

-- 1. Buat Tabel Baru yang BERSIH
CREATE TABLE clean_medical_sales AS
SELECT 
    "Invoice",
    "StockCode",
    "Description",
    "Quantity",
    "InvoiceDate",
    "Price",
    "Customer ID",
    "Product_Category",
    "Product_Name",
    ("Quantity" * "Price") AS total_amount -- Hitung Total Belanja per item
FROM raw_medical_sales
WHERE 
    "Invoice" NOT LIKE 'C%'       -- Buang Transaksi Batal/Retur
    AND "Customer ID" IS NOT NULL 
    and "Customer ID" != '' -- Buang Pasien Tanpa ID
    AND "Price" > 0               -- Buang Harga Error/Nol
    AND "Quantity" > 0            -- Buang Quantity Negatif
    AND "Product_Category" != 'Administrative'; -- Buang Ongkir/Diskon
    
    
alter table clean_medical_sales 
rename column "Customer ID" to customer_id;

alter table clean_medical_sales 
alter column customer_id type integer using customer_id::numeric::integer;

-- 3. Cek Hasil Cleaning
SELECT * FROM clean_medical_sales LIMIT 10;



-- RFM Analysis-----------------

CREATE TABLE rfm_metrics_saved AS
WITH reference_date AS (
    -- Kita ambil tanggal max + 1 hari sebagai acuan "Hari Ini"
    SELECT MAX("InvoiceDate")::date + INTERVAL '1 day' AS ref_date 
    FROM clean_medical_sales
)
SELECT 
    customer_id,
    -- Hitung Recency
    DATE_PART('day', (SELECT ref_date FROM reference_date) - MAX("InvoiceDate")::date) AS recency_days,
    -- Hitung Frequency
    COUNT(DISTINCT "Invoice") AS frequency_count,
    -- Hitung Monetary
    SUM(total_amount) AS monetary_value
FROM clean_medical_sales
GROUP BY customer_id;

-- Cek apakah tabel berhasil dibuat
SELECT * FROM rfm_metrics_saved LIMIT 5;


-----------RFM Scores--------------------------------------
CREATE TABLE rfm_scores AS
SELECT 
    customer_id,
    recency_days,
    frequency_count,
    monetary_value,
    
    -- SCORING RECENCY (Makin KECIL harinya, makin TINGGI skornya 5)
    NTILE(5) OVER (ORDER BY recency_days DESC) as r_score,
    
    -- SCORING FREQUENCY (Makin BANYAK, makin TINGGI skornya 5)
    NTILE(5) OVER (ORDER BY frequency_count ASC) as f_score,
    
    -- SCORING MONETARY (Makin BANYAK, makin TINGGI skornya 5)
    NTILE(5) OVER (ORDER BY monetary_value ASC) as m_score

FROM rfm_metrics_saved; -- <-- Perhatikan kita ambil dari tabel yang sudah disimpan

-- Cek Hasil Akhir
SELECT * FROM rfm_scores ORDER BY m_score DESC LIMIT 10;


--RFM Segmentation-------------------------
CREATE TABLE final_rfm_segmentation AS
SELECT 
    customer_id,
    recency_days,
    frequency_count,
    monetary_value,
    r_score,
    f_score,
    m_score,
    
    -- Menggabungkan skor R dan F agar mudah dibaca (opsional)
    CONCAT(r_score, f_score) AS rf_score,

    -- LOGIKA SEGMENTASI (Penting!)
    CASE 
        -- 1. CHAMPIONS (Baru belanja, Sering belanja)
        WHEN r_score = 5 AND f_score = 5 THEN 'Champions (Sultan)'
        WHEN r_score = 5 AND f_score = 4 THEN 'Champions (Sultan)'
        
        -- 2. LOYAL CUSTOMERS (Sering belanja, tapi terakhir agak lama)
        WHEN r_score BETWEEN 3 AND 4 AND f_score BETWEEN 4 AND 5 THEN 'Loyal Customers'
        
        -- 3. POTENTIAL LOYALIST (Baru belanja, belum terlalu sering)
        WHEN r_score BETWEEN 4 AND 5 AND f_score BETWEEN 2 AND 3 THEN 'Potential Loyalist'
        
        -- 4. NEW CUSTOMERS (Baru belanja sekali/dua kali)
        WHEN r_score = 5 AND f_score = 1 THEN 'New Customers'
        
        -- 5. NEED ATTENTION (Sudah mulai jarang muncul)
        WHEN r_score BETWEEN 3 AND 4 AND f_score BETWEEN 1 AND 3 THEN 'Need Attention'
        
        -- 6. AT RISK (Dulu sering belanja, sekarang menghilang! BAHAYA)
        WHEN r_score BETWEEN 1 AND 2 AND f_score BETWEEN 3 AND 5 THEN 'At Risk (Bahaya)'
        
        -- 7. LOST / HIBERNATING (Sudah lama hilang, jarang belanja pula)
        ELSE 'Hibernating / Lost'
    END AS customer_segment

FROM rfm_scores;

-- Cek Hasil Akhir 
SELECT * FROM final_rfm_segmentation 
ORDER BY r_score DESC, f_score DESC 
LIMIT 20;