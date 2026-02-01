DROP DATABASE IF EXISTS ESG_BALANCE;
CREATE DATABASE ESG_BALANCE;
USE ESG_BALANCE;

-- CREAZIONE TABELLE:
CREATE TABLE UTENTE (
    Username VARCHAR(50) PRIMARY KEY,
    CF CHAR(16) NOT NULL UNIQUE,
    Password VARCHAR(255) NOT NULL, 
    DataNascita DATE NOT NULL,
    LuogoNascita VARCHAR(50)
) engine = INNODB;

CREATE TABLE EMAIL (
    Username VARCHAR(50),
    Email VARCHAR(50) UNIQUE,
    PRIMARY KEY (Username, Email),
    FOREIGN KEY (Username) REFERENCES UTENTE(Username) ON DELETE CASCADE
) engine = INNODB;

-- SPECIALIZZAZIONI UTENTE ---------------------------------------------
/* ho preferito utilizzare la soluzione tre studiata in aula, 
in quanto accorpare tutto nell'entità padre sarebbe stato problematico */
CREATE TABLE AMMINISTRATORE (
    Username VARCHAR(50) PRIMARY KEY,
    FOREIGN KEY (Username) REFERENCES UTENTE(Username) ON DELETE CASCADE
) engine = INNODB;

CREATE TABLE REVISORE_ESG (
    Username VARCHAR(50) PRIMARY KEY,
    NRev INT,
    IndiceAffidabilita DECIMAL(5,2),
    FOREIGN KEY (Username) REFERENCES UTENTE(Username) ON DELETE CASCADE
) engine = INNODB;
-- COMPETENZA (Revisore ha una lista di competenze) ----------------------------
CREATE TABLE COMPETENZA (
    Username VARCHAR(50),
    NomeCompetenza VARCHAR(100),
    Livello INT CHECK (Livello BETWEEN 0 AND 5),
    PRIMARY KEY (Username, NomeCompetenza),
    FOREIGN KEY (Username) REFERENCES REVISORE_ESG(Username)
)  engine = INNODB;

CREATE TABLE RESPONSABILE_AZIENDALE (
    Username VARCHAR(50) PRIMARY KEY,
    Curriculum VARCHAR(255), -- scelgo di mettere il percorso del file invece che inserirlo direttamente nel DB
    FOREIGN KEY (Username) REFERENCES UTENTE(Username) ON DELETE CASCADE
)  engine = INNODB;

-- AZIENDA --------------------------------------------------------------------------------------------------
CREATE TABLE AZIENDA (
    RagioneSociale VARCHAR(150) PRIMARY KEY,
    PartitaIva CHAR(11) UNIQUE,
    Settore VARCHAR(100),
    NumDipendenti INT,
    Nome VARCHAR(150),
    Logo VARCHAR(255), -- invece di mettere l'immagine inserisco il percorso
    NumBilanci INT,
    UsernameResponsabile VARCHAR(50) NOT NULL,
    FOREIGN KEY (UsernameResponsabile) REFERENCES RESPONSABILE_AZIENDALE(Username)
)  engine = INNODB;

-- BILANCIO ESERCIZIO ------------------------------------------------------------------------
CREATE TABLE BILANCIO_ESERCIZIO (
    IDBilancio INT AUTO_INCREMENT PRIMARY KEY,
    DataCreazione DATE,
    Stato ENUM('bozza','in revisione','approvato','respinto') DEFAULT 'bozza',
    RagioneSocialeAzienda VARCHAR(150),
    FOREIGN KEY (RagioneSocialeAzienda) REFERENCES AZIENDA(RagioneSociale)
) engine = INNODB;

-- VOCE CONTO (inserita da utente amministratore) -------------------------------------------
CREATE TABLE VOCE_CONTO (
    Nome VARCHAR(100) PRIMARY KEY,
    Descrizione VARCHAR(100),
    UsernameAmministratore VARCHAR(50),
    FOREIGN KEY (UsernameAmministratore) REFERENCES AMMINISTRATORE(Username)
) engine = INNODB;

-- VOCE BILANCIO (dipende da bilancio + voce conto) --------------------------------------------
CREATE TABLE VOCE_BILANCIO (
    NomeVoceConto VARCHAR(100),
    IDBilancio INT,
    ValoreNumerico INT NOT NULL,
    PRIMARY KEY (NomeVoceConto, IDBilancio),
    UNIQUE (IDBilancio, ValoreNumerico), -- lo metto anche se sarebbe già garantito...
    FOREIGN KEY (NomeVoceConto) REFERENCES VOCE_CONTO(Nome),
    FOREIGN KEY (IDBilancio) REFERENCES BILANCIO_ESERCIZIO(IDBilancio) ON DELETE CASCADE
) engine = INNODB;

-- INDICATORE ESG (tipizzato e inserito da un amministratore) -------------------------------
-- qui invece ho deciso di adottare la soluzione 1 vista in aula, cioè
-- accorpare le entità figlie nel padre aggiungendo l'attributo Tipo
CREATE TABLE INDICATORE_ESG (
    Nome VARCHAR(150) PRIMARY KEY,
    Immagine VARCHAR(255),
    Rilevanza INT CHECK (Rilevanza BETWEEN 0 AND 10),
    CodiceNormativa VARCHAR(50),
    Ambito VARCHAR(50),
    FreqRilevazione VARCHAR(50),
    Tipo VARCHAR(50),
    UsernameAmministratore VARCHAR(50),
    FOREIGN KEY (UsernameAmministratore) REFERENCES AMMINISTRATORE(Username)
) engine = INNODB;

-- ASSOCIA (VoceBilancio - Indicatore) M:N con attributi --------------------------------------------
CREATE TABLE ASSOCIA (
    NomeVoceConto VARCHAR(100),
    IDBilancio INT,
    NomeIndicatore VARCHAR(150),
    DataRilevazione DATE,
    ValIndicatore DECIMAL(15,2),
    Fonte VARCHAR(200),
    
    PRIMARY KEY (NomeVoceConto, IDBilancio, NomeIndicatore, DataRilevazione),
    
    FOREIGN KEY (NomeVoceConto, IDBilancio) REFERENCES VOCE_BILANCIO(NomeVoceConto, IDBilancio),
    FOREIGN KEY (NomeIndicatore) REFERENCES INDICATORE_ESG(Nome)
) engine = INNODB;

-- VALUTAZIONE BILANCIO (Revisore valuta bilancio) ---------------------------------------------------
-- qui vengono seguiti due step: prima un amministratore associa un revisore ad un bilancio
-- e quindi di default i tre campi del giudizio sono vuoti
-- poi il revisore modifica il record aggiungendo un giudizio
CREATE TABLE VALUTA_BILANCIO (
    UsernameRevisore VARCHAR(50),
    IDBilancio INT,
    Esito ENUM('approvazione','approvazione con rilievi','respingimento'),
    Data DATE,
    CampoRilievi TEXT,
    
    PRIMARY KEY (UsernameRevisore, IDBilancio),
    FOREIGN KEY (UsernameRevisore) REFERENCES REVISORE_ESG(Username),
    FOREIGN KEY (IDBilancio) REFERENCES BILANCIO_ESERCIZIO(IDBilancio)
) engine = INNODB;

-- NOTA (nota che inserisce il revisore ad una voce di bilancio) -------------
CREATE TABLE NOTA (
    IdNota INT AUTO_INCREMENT PRIMARY KEY,
    Data DATE,
    Testo TEXT,
    RevisoreEmittente VARCHAR(50),
    NomeVoceConto VARCHAR(100),
    IDBilancio INT,
    
    FOREIGN KEY (RevisoreEmittente) REFERENCES REVISORE_ESG(Username),
    FOREIGN KEY (NomeVoceConto, IDBilancio) REFERENCES VOCE_BILANCIO(NomeVoceConto, IDBilancio)
) engine = INNODB;

/*------------------------- PROCEDURE PER INSERIRE GLI UTENTI NEL SISTEMA: --------------------------------------------------------------------------*/
-- in particolare creo delle stored procedures per inserire gli utenti, in quanto è un processo delicato:
-- l'inserimento può avvenire solo con queste procedure, perchè ogni utente appartiene perforza ad una categoria (amministratore, revisore o responsabile)
-- NON PUò ESISTERE UN RECORD DI UTENTE CHE NON FACCIA PARTE DI UNA SPECIFICAZIONE:
DELIMITER $$
CREATE PROCEDURE InserisciAmministratore(IN us VARCHAR(50), IN pw VARCHAR(255), IN cf CHAR(16), IN d DATE, IN l VARCHAR(50), IN primaEmail VARCHAR(50))
BEGIN
    START TRANSACTION;
        INSERT INTO UTENTE(Username, Password, CF, DataNascita, LuogoNascita)
        VALUES (us, pw, cf, d, l);
        
        INSERT INTO AMMINISTRATORE(Username)
        VALUES (us);
        
        -- Inserisco il primo recapito obbligatorio
        INSERT INTO EMAIL(Username, Email)
        VALUES (us, primaEmail);
    COMMIT;
END $$
DELIMITER ;

DELIMITER $$
CREATE PROCEDURE InserisciRevisore(IN us VARCHAR(50), IN pw VARCHAR(255), IN cf CHAR(16), IN d DATE, IN l VARCHAR(50), IN primaEmail VARCHAR(50))
BEGIN
    START TRANSACTION;
        INSERT INTO UTENTE(Username, Password, CF, DataNascita, LuogoNascita)
        VALUES (us, pw, cf, d, l);
        
        INSERT INTO REVISORE_ESG(Username, NRev, IndiceAffidabilita)
        VALUES (us, 0, 0.00);
        
        -- Inserisco il primo recapito obbligatorio
        INSERT INTO EMAIL(Username, Email)
        VALUES (us, primaEmail);
    COMMIT;
END $$
DELIMITER ;

DELIMITER $$
CREATE PROCEDURE InserisciResponsabile(IN us VARCHAR(50), IN pw VARCHAR(255), IN cf CHAR(16), IN d DATE, IN l VARCHAR(50), IN curriculum VARCHAR(255), IN primaEmail VARCHAR(50))
BEGIN
    START TRANSACTION;
        INSERT INTO UTENTE(Username, Password, CF, DataNascita, LuogoNascita)
        VALUES (us, pw, cf, d, l);
        
        INSERT INTO RESPONSABILE_AZIENDALE(Username, Curriculum)
        VALUES (us, curriculum);
        
        -- Inserisco il primo recapito obbligatorio
        INSERT INTO EMAIL(Username, Email)
        VALUES (us, primaEmail);
    COMMIT; -- Conferma l'inserimento solo se tutti hanno successo
END $$
DELIMITER ;

DELIMITER $$
CREATE PROCEDURE AggiungiEmail (IN us VARCHAR(50), IN email VARCHAR(50))
BEGIN
    INSERT INTO EMAIL(Username, Email) VALUES (us, email);
END $$
DELIMITER ;

/* inseriamo amministratore un amministratore: */
CALL InserisciAmministratore('amministratore1', 'pwAmm1', 'CFAMMIN01A01H501', '1985-01-01', 'Pieve di Cento', 'primaEmail@ciao');

-- LOGIN UTENTE
DELIMITER $$ 
CREATE PROCEDURE LoginUtente(IN username VARCHAR(50), IN pw VARCHAR(255))
BEGIN
	DECLARE risultato BOOL DEFAULT false;
    
    -- Metto risultato a TRUE solo se l'utente è già resgistrato 
    SELECT COUNT(*) > 0 AS risultato
    FROM UTENTE
    WHERE Username = username AND Password = pw;
END
$$ DELIMITER ;

DELIMITER $$
CREATE PROCEDURE ModificaPassword(IN us VARCHAR(50),  IN vecchiaPw VARCHAR(255),  IN nuovaPw VARCHAR(255))
BEGIN
    DECLARE pwAttuale VARCHAR(255);
    
    -- 1. Recuperiamo la password attuale per l'utente specificato
    SELECT Password INTO pwAttuale 
    FROM UTENTE 
    WHERE Username = us;

    -- 2. Facciamo i controlli 
    IF pwAttuale IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Errore: Utente non trovato.';
    ELSEIF pwAttuale <> vecchiaPw THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Errore: La vecchia password non è corretta.';
    ELSEIF vecchiaPw = nuovaPw THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Errore: La nuova password deve essere diversa da quella attuale.';
    ELSE
        -- 4. Se tutto è ok, procediamo con l'aggiornamento
        UPDATE UTENTE 
        SET Password = nuovaPw 
        WHERE Username = us;
    END IF;
END $$
DELIMITER ;

/*---------------------------------------- PROCEDURE VALIDE SOLO PER GLI UTENTI AMMINISTRATORI -----------------------------------------------*/
-- POPOLAMENTO DELLA LISTA DEGLI INDICATORI ESG
DELIMITER $$ 
CREATE PROCEDURE InserisciIndicatoreESG(
    IN nome VARCHAR(150), IN img VARCHAR(255), IN ril INT,
    IN cod VARCHAR(50), IN amb VARCHAR(50), IN freq VARCHAR(50),
    IN tipo VARCHAR(50), IN usAmm VARCHAR(50)
)
BEGIN
	-- CONTROLLO SICUREZZA
    IF NOT EXISTS (SELECT 1 FROM AMMINISTRATORE WHERE Username = usAmm) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'NON SEI UN AMMINISTRATOREEEEE!!!';
    ELSE
		INSERT INTO INDICATORE_ESG (Nome, Immagine, Rilevanza, CodiceNormativa, Ambito, FreqRilevazione, Tipo, UsernameAmministratore)
		VALUES (nome, img, ril, cod, amb, freq, tipo, usAmm);
		-- visto che inserisco tutti i dati posso evistare di specificare gli attributi della tabella
	END IF;
END
$$ DELIMITER ;

-- CREAZIONE DEL TEMPLATE DEL BILANCIO D'ESERCIZIO == POPOLAMENTO DELLA LISTA DELLE VOCI DEI CONTI
DELIMITER $$ 
CREATE PROCEDURE InserisciVoceConto(n VARCHAR(80), descr VARCHAR(100), usAmm VARCHAR(50))
BEGIN
	-- CONTROLLO SICUREZZA LOGICA
    IF NOT EXISTS (SELECT 1 FROM AMMINISTRATORE WHERE Username = usAmm) THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'NON SEI UN AMMINISTRATOREEEEE!!!';
    ELSE
		INSERT INTO VOCE_CONTO VALUES (n, descr, usAmm);
    END IF;
END
$$ DELIMITER ;

-- ASSOCIAZIONE DI UN REVISORE ESG AD UN BILANCIO AZIENDALE
DELIMITER $$
CREATE PROCEDURE AssegnaRevisoreABilancio(IN usRev VARCHAR(50), IN idBil INT, IN usAmm VARCHAR(50))
BEGIN
	-- controllo se chi fa l'operazione è un amministratore
	IF NOT EXISTS (SELECT 1 FROM AMMINISTRATORE WHERE Username = usAmm) THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'NON SEI UN AMMINISTRATOREEEEE!!!';
	
    -- 2. Controllo se il destinatario scelto è un Revisore
    ELSEIF NOT EXISTS (SELECT 1 FROM REVISORE_ESG WHERE Username = usRev) THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'SCEGLIERE UN REVISOREEEE!!!';

    -- 3. Controllo se il bilancio scelto esiste
    ELSEIF NOT EXISTS (SELECT 1 FROM BILANCIO_ESERCIZIO WHERE IDBilancio = idBil) THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'SCEGLIERE UN BILANCIO ESISTENTEEEE!!!';
    ELSE
		INSERT INTO VALUTA_BILANCIO(UsernameRevisore, IDBilancio) VALUES (usRev, idBil);
	END IF;
END $$
DELIMITER ;

/*---------------------------------------- PROCEDURE VALIDE SOLO PER GLI UTENTI REVISORI ESG ---------------------------------------------------*/
-- Inserimento delle proprie competenze
DELIMITER $$
CREATE PROCEDURE InserisciCompetenza(IN usRev VARCHAR(50), IN nomeComp VARCHAR(100), IN liv INT)
BEGIN
	IF NOT EXISTS (SELECT 1 FROM REVISORE_ESG WHERE Username = usRev) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'NON SEI UN REVISOREEEE!!!';
	ELSE
		INSERT INTO COMPETENZA(Username, NomeCompetenza, Livello) VALUES (usRev, nomeComp, liv);
	END IF;
END 
$$ DELIMITER ;

-- Eliminazione di una delle competenze del revisore ESG
DELIMITER $$
CREATE PROCEDURE EliminaCompetenza(IN usRev VARCHAR(50), IN nomeComp VARCHAR(100))
BEGIN
	IF NOT EXISTS (SELECT 1 FROM REVISORE_ESG WHERE Username = usRev) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'NON SEI UN REVISOREEEE!!!';
	ELSE
		DELETE FROM COMPETENZA WHERE Username = usRev AND NomeCompetenza = nomeComp;
	END IF;
END $$
DELIMITER ;

-- Inserimento note su singole voci di bilancio
DELIMITER $$
CREATE PROCEDURE InserisciNotaSuVoceBilancio(IN testoNota TEXT, IN usRev VARCHAR(50), IN nomeVoce VARCHAR(100), IN idBil INT)
    -- assumo che la data sia quella corrente, quindi non la prendo come input
    -- anche idNota ho messo che è un auto_increment primary key, quindi gestisce tutto il DB.
BEGIN
	IF NOT EXISTS (SELECT 1 FROM REVISORE_ESG WHERE Username = usRev) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'NON SEI UN REVISOREEEE!!!';
	ELSE
		INSERT INTO NOTA(Data, Testo, RevisoreEmittente, NomeVoceConto, IDBilancio)
		VALUES (CURRENT_DATE, testoNota, usRev, nomeVoce, idBil);
	END IF;
END 
$$ DELIMITER ;

-- Inserimento del giudizio complessivo (Valutazione Finale)
-- Il revisore non crea una nuova riga (perché l'amministratore lo ha già assegnato), 
-- ma aggiorna quella esistente. Questo attiverà il secondo trigger per il controllo della chiusura del bilancio.
DELIMITER $$
CREATE PROCEDURE InserisciGiudizioRevisore(IN usRev VARCHAR(50), IN idBil INT, IN esito ENUM('approvazione','approvazione con rilievi','respingimento'),
    IN rilievi TEXT)
BEGIN
	IF NOT EXISTS (SELECT 1 FROM REVISORE_ESG WHERE Username = usRev) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'NON SEI UN REVISOREEEE!!!';
	ELSE
		UPDATE VALUTA_BILANCIO SET Esito = esito, Data = CURRENT_DATE, CampoRilievi = rilievi
		WHERE UsernameRevisore = usRev AND IDBilancio = idBil;
    END IF;
END $$
DELIMITER ;

/* ------------------------------------- PROCEDURE VALIDE SOLO PER GLI UTENTI RESPONSABILI AZIENDALI --------------------------------------------*/
-- Registrazione di un'azienda
DELIMITER $$
CREATE PROCEDURE RegistraAzienda(IN rs VARCHAR(150), IN pi CHAR(11), IN sett VARCHAR(100), IN nDip INT, IN n VARCHAR(150), IN logo VARCHAR(255), IN usResp VARCHAR(50))
    -- il NumBilanci, ovviamente, appena creata l'azienda sarà pari a zero, quindi non mi serve in input 
BEGIN
	IF NOT EXISTS (SELECT 1 FROM RESPONSABILE_AZIENDALE WHERE Username = usResp) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'NON SEI UN RESPONDABILEEEEEE!!!';
	ELSE
		INSERT INTO AZIENDA(RagioneSociale, PartitaIva, Settore, NumDipendenti, Nome, Logo, NumBilanci, UsernameResponsabile)
		VALUES (rs, pi, sett, nDip, n, logo, 0, usResp);
	END IF;
END 
$$ DELIMITER ;

/*-- Creazione/Popolamento di un nuovo bilancio 
-- RICORDA (Stato di default 'bozza') e ID_Bilancio è un atuo_increment (=viene implementata direttamente dal DB)
DELIMITER $$ 
CREATE PROCEDURE CreaBilancio(IN rsAzienda VARCHAR(150), IN dataC DATE)
BEGIN
	-- variabile dove memorizzerò l'id che il database assegna al nuovo bilancio
    DECLARE nuovo_id INT;

    -- CONTROLLO BILANCIO ANNUALE --> Se esiste già un bilancio per l'azienda nello stesso anno, blocca tutto
	IF EXISTS (
		SELECT 1 FROM BILANCIO_ESERCIZIO 
		WHERE RagioneSocialeAzienda = rsAzienda 
		AND YEAR(DataCreazione) = YEAR(dataC)
	) THEN
		SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Errore: Esiste gia un bilancio per questa azienda nell''anno selezionato.';
	END IF;

	-- CREAZIONE BILANCIO (Stato 'bozza' di default)
	INSERT INTO BILANCIO_ESERCIZIO(DataCreazione, Stato, RagioneSocialeAzienda)
	VALUES (dataC, 'bozza', rsAzienda);

	-- Recupero l'ID del bilancio appena generato (super figa questa funzione grz centro software) 
    SET nuovo_id = LAST_INSERT_ID();

    -- 3. INSERIMENTO NEL BILANCIO DEL TEMPLATE (Voci Conto)
    -- setto come valore numerico 0.00, in quanto all'atto di creazione le voci sono a 0
    INSERT INTO VOCE_BILANCIO (NomeVoceConto, IDBilancio, ValoreNumerico)
    SELECT Nome, nuovo_id, 0.00
    FROM VOCE_CONTO;
END
$$ DELIMITER ;*/

DELIMITER $$ 
CREATE PROCEDURE CreaBilancio(IN rsAzienda VARCHAR(150), IN dataC DATE, IN usResp VARCHAR(50))
BEGIN
	DECLARE nuovo_id INT;
    
    -- FACCIO IL CONTROLLO
	IF NOT EXISTS (SELECT 1 FROM RESPONSABILE_AZIENDALE WHERE Username = usResp) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'NON SEI UN RESPONDABILEEEEEE!!!';
	END IF;

    -- 1. CONTROLLO BILANCIO ANNUALE
    IF EXISTS (
        SELECT 1 FROM BILANCIO_ESERCIZIO 
        WHERE RagioneSocialeAzienda = rsAzienda 
        AND YEAR(DataCreazione) = YEAR(dataC)
    ) THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Errore: Esiste gia un bilancio per questa azienda nell''anno selezionato.';
    END IF;

    -- 2. CREAZIONE RECORD PADRE
    INSERT INTO BILANCIO_ESERCIZIO(DataCreazione, Stato, RagioneSocialeAzienda)
    VALUES (dataC, 'bozza', rsAzienda);

    SET nuovo_id = LAST_INSERT_ID();
    
    -- 4. INSERIMENTO VOCI CON NUMERAZIONE PROGRESSIVA
    -- Inizializziamo @curr_row a 0 e lo incrementiamo per ogni riga inserita
    SET @curr_row := 0;
    
    INSERT INTO VOCE_BILANCIO (NomeVoceConto, IDBilancio, ValoreNumerico)
    SELECT Nome, nuovo_id, (@curr_row := @curr_row + 1)
    FROM VOCE_CONTO
    ORDER BY Nome; 
END $$ 
DELIMITER ;

/*-- inserimento dei valori monetari*/
/*DELIMITER $$
CREATE PROCEDURE InserisciImportoVoce(IN id_bil INT, IN nome_voce VARCHAR(100), IN importo DECIMAL(15,2))
BEGIN
    DECLARE stato_attuale VARCHAR(20);

    -- Recuperiamo lo stato del bilancio
    SELECT Stato INTO stato_attuale 
    FROM BILANCIO_ESERCIZIO 
    WHERE IDBilancio = id_bil;

    -- solo se il bilancio è in bozza posso modificare gli importi
    IF stato_attuale = 'bozza' THEN
        UPDATE VOCE_BILANCIO 
        SET ValoreNumerico = importo
        WHERE IDBilancio = id_bil AND NomeVoceConto = nome_voce;
    END IF;
END $$
DELIMITER ;*/

-- Inserimento dei valori degli indicatori ESG per le singole voci di bilancio
-- prendo la data corrente (mi sembra una cosa giusta)
DELIMITER $$ 
CREATE PROCEDURE AssociaValoreESG(IN nomeVoce VARCHAR(100), IN idBil INT, IN nomeInd VARCHAR(150),  IN valore DECIMAL(15,2), IN fonteRil VARCHAR(200), IN usResp VARCHAR(50))
BEGIN
	-- FACCIO IL CONTROLLO
	IF NOT EXISTS (SELECT 1 FROM RESPONSABILE_AZIENDALE WHERE Username = usResp) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'NON SEI UN RESPONDABILEEEEEE!!!';
	END IF;
    
    INSERT INTO ASSOCIA(NomeVoceConto, IDBilancio, NomeIndicatore, DataRilevazione, ValIndicatore, Fonte)
    VALUES (nomeVoce, idBil, nomeInd, CURRENT_DATE, valore, fonteRil);
END 
$$ DELIMITER ; 

/* ---------------------------- STATISTICHE IMPLEMENTATE CON LE VISTE: ---------------------------------------------*/

-- 1) Mostrare il numero di aziende registrate in piattaforma 
CREATE VIEW NAziendeRegistrate AS (
SELECT COUNT(*) AS TotaleAziende
FROM AZIENDA);

-- 2) Mostrare il numero di revisori esg in piattaforma
CREATE VIEW NUtentiRevisori AS (
SELECT COUNT(*) AS TotaleRevisori
FROM REVISORE_ESG);

-- 3) azienda con maggiore affidabilità
-- aff = percentuale di bilanci approvati dai revisori senza rilievi 
-- !!! SE USO IL LIMIT NON VA BENE --> prendo una sola anche se magari ci sono due aziende a parimerito
CREATE VIEW AziendaPiuAffidabile AS
WITH ConteggioEsiti AS (
    -- Step 1: Dobbiamo unire le valutazioni ai bilanci per risalire all'azienda
    SELECT B.RagioneSocialeAzienda AS Azienda, COUNT(*) AS TotaleValutati,
        SUM(VB.Esito = 'approvazione') AS TotaleApprovati 
    FROM VALUTA_BILANCIO VB JOIN BILANCIO_ESERCIZIO B ON VB.IDBilancio = B.IDBilancio
    WHERE VB.Esito IS NOT NULL 
    GROUP BY B.RagioneSocialeAzienda
),
Percentuali AS (
    -- Step 2: Calcolo percentuale
    SELECT Azienda, (TotaleApprovati / TotaleValutati) * 100 AS Percentuale
    FROM ConteggioEsiti
)
-- Step 3: Selezione con gestione parimerito
SELECT Azienda AS RagioneSociale, Percentuale AS PercentualeAffidabilita
FROM Percentuali
WHERE Percentuale = (SELECT MAX(Percentuale) FROM Percentuali);

-- 4)
CREATE VIEW ClassificaBilanci AS (
    SELECT B.IDBilancio, B.RagioneSocialeAzienda, B.DataCreazione,
           COUNT(S.NomeIndicatore) AS TotaleIndicatoriAssegnati
    FROM BILANCIO_ESERCIZIO as B 
    LEFT JOIN ASSOCIA as S ON B.IDBilancio = S.IDBilancio
    GROUP BY B.IDBilancio, B.RagioneSocialeAzienda, B.DataCreazione
    ORDER BY TotaleIndicatoriAssegnati DESC
);

-- 5)
CREATE VIEW VistaAssegnazioniRevisori AS (
    SELECT 
        B.IDBilancio, 
        B.RagioneSocialeAzienda AS Azienda, 
        B.Stato AS StatoBilancio, 
        VB.UsernameRevisore AS Revisore,
        --  aggiungo una colonna che controlla se il revisore ha 
        -- già espresso il giudizio o meno
        CASE 
            WHEN VB.Esito IS NOT NULL THEN 'Voto Espresso'
            ELSE 'In Attesa'
        END AS StatoGiudizioRevisore
    FROM BILANCIO_ESERCIZIO B 
    LEFT JOIN VALUTA_BILANCIO VB ON B.IDBilancio = VB.IDBilancio
    ORDER BY B.IDBilancio
);

/* ----------------------------------------------------- TRIGGER -----------------------------------------------------------*/

-- 1) cambio lo stato :"in revisione" quando viene aggiunto un revisore ad un bilancio
DELIMITER $$
CREATE TRIGGER StatoInRevisione AFTER INSERT ON VALUTA_BILANCIO
FOR EACH ROW
BEGIN
    UPDATE BILANCIO_ESERCIZIO SET Stato = 'in revisione'
    WHERE IDBilancio = NEW.IDBilancio 
	AND Stato = 'bozza'; 
      -- Cambia solo se è ancora in bozza per non sovrascrivere stati successivi
END $$
DELIMITER ;

-- 2) Aggiorno lo stato finale 
DELIMITER $$
CREATE TRIGGER AggiornaStatoFinaleBilancio AFTER UPDATE ON VALUTA_BILANCIO
FOR EACH ROW
BEGIN
    DECLARE n_revisori_tot INT;
    DECLARE n_revisori_voto INT;
    DECLARE n_respingimenti INT;

    -- Conta quanti revisori sono stati assegnati a questo bilancio
    SELECT COUNT(*) INTO n_revisori_tot
    FROM VALUTA_BILANCIO
    WHERE IDBilancio = NEW.IDBilancio;

    -- Conta quanti hanno effettivamente inserito l'esito
    SELECT COUNT(*) INTO n_revisori_voto
    FROM VALUTA_BILANCIO
    WHERE IDBilancio = NEW.IDBilancio AND Esito IS NOT NULL;

    -- Se tutti hanno votato, decidiamo lo stato finale
    IF n_revisori_tot = n_revisori_voto THEN
        -- Controlliamo se c'è almeno un respingimento
        SELECT COUNT(*) INTO n_respingimenti
        FROM VALUTA_BILANCIO
        WHERE IDBilancio = NEW.IDBilancio AND Esito = 'respingimento';

        IF n_respingimenti > 0 THEN
            UPDATE BILANCIO_ESERCIZIO SET Stato = 'respinto' WHERE IDBilancio = NEW.IDBilancio;
        ELSE
            UPDATE BILANCIO_ESERCIZIO SET Stato = 'approvato' WHERE IDBilancio = NEW.IDBilancio;
        END IF;
    END IF;
END $$
DELIMITER ;

-- CREATO DA ME.... MOLTO UTILE!!!
DELIMITER $$
CREATE TRIGGER AggiornaBilanciDopoNuovaVoce AFTER INSERT ON VOCE_CONTO
FOR EACH ROW
BEGIN
    -- Inserisce la nuova voce di conto in VOCE_BILANCIO ma solo nei bilanci in stato 'Bozza'
    -- in quanto non posso aggiungere voci in bilanci praticamente chiusi.
    INSERT INTO VOCE_BILANCIO (NomeVoceConto, IDBilancio, ValoreNumerico)
    SELECT NEW.Nome, B.IDBilancio, (SELECT IFNULL(MAX(ValoreNumerico), 0) + 1 
									FROM VOCE_BILANCIO 
									WHERE IDBilancio = B.IDBilancio)
    FROM BILANCIO_ESERCIZIO B
    WHERE B.Stato = 'bozza'; 
END $$
DELIMITER ;

DELIMITER $$

CREATE TRIGGER IncrementaConteggioBilanci AFTER INSERT ON BILANCIO_ESERCIZIO
FOR EACH ROW
BEGIN
    -- Aggiorna la tabella AZIENDA incrementando l'attributo NumBilanci
    -- Usiamo NEW.RagioneSocialeAzienda per identificare l'azienda del bilancio appena inserito
    UPDATE AZIENDA
    SET NumBilanci = NumBilanci + 1
    WHERE RagioneSociale = NEW.RagioneSocialeAzienda;
END $$
DELIMITER ;

-- INCREMENTA NRev ad un revisore ogni volta che esprime il giudizio
-- ho dato per scontato che tanto più lavora, tanto più un Revisore è affidabile
DELIMITER $$
CREATE TRIGGER AggiornaNRev AFTER UPDATE ON VALUTA_BILANCIO
FOR EACH ROW
BEGIN
    -- Se il revisore ha appena completato la valutazione
    IF OLD.Esito IS NULL AND NEW.Esito IS NOT NULL THEN
        UPDATE REVISORE_ESG 
        SET NRev = IFNULL(NRev, 0) + 1 
        WHERE Username = NEW.UsernameRevisore;
    END IF;
END $$
DELIMITER ;

-- AGGIORNA L'INDICE DI AFFIDABILITA DEL RESVISORE OGNI VOLTA CHE QUESTO COMPLETA UN BILANCIO
DELIMITER $$
CREATE TRIGGER RicalcolaAffidabilitaRevisore AFTER UPDATE ON VALUTA_BILANCIO
FOR EACH ROW
BEGIN
	-- Se il revisore ha appena completato la valutazione
    IF OLD.Esito IS NULL AND NEW.Esito IS NOT NULL THEN
        
        -- L'affidabilità aumenta di 0.5 per ogni revisione conclusa fino a un massimo di 100
        UPDATE REVISORE_ESG 
        SET IndiceAffidabilita = LEAST(100.00, IndiceAffidabilita + 0.50)
        WHERE Username = NEW.UsernameRevisore;
    END IF;
END $$
DELIMITER ;


/*----------------------------------------------------------- CANCELLAZIONI SICURE  ------------------------------------------------------*/
DELIMITER $$
CREATE PROCEDURE EliminaUtente(IN usUtente VARCHAR(50))
BEGIN
    -- 1. Eliminiamo il record dalla tabella padre UTENTE.
    -- Grazie al ON DELETE CASCADE che abbiamo messo nelle tabelle figlie,
    -- questa operazione cancellerà AUTOMATICAMENTE il record in AMMINISTRATORE o REVISORE o RESPONSABILE.
    -- E, cosa fondamentale, questo attiverà i tuoi TRIGGER BEFORE DELETE 
    -- che faranno la pulizia (UPDATE a NULL e cancellazione email).
    
    DELETE FROM UTENTE WHERE Username = usUtente;
    
END $$
DELIMITER ;

-- cancella amministratore. 
DELIMITER $$
CREATE TRIGGER CancellaTuttoAmministratore BEFORE DELETE ON AMMINISTRATORE
FOR EACH ROW
BEGIN
    -- Scolleghiamo i dati per non perderli (Nulling)
    UPDATE VOCE_CONTO SET UsernameAmministratore = NULL 
    WHERE UsernameAmministratore = OLD.Username;
    
    UPDATE INDICATORE_ESG SET UsernameAmministratore = NULL 
    WHERE UsernameAmministratore = OLD.Username;

    -- Puliamo le email (anche se c'è il CASCADE, farlo qui è più sicuro se vuoi controllo)
    DELETE FROM EMAIL WHERE Username = OLD.Username;
END $$
DELIMITER ;

DELIMITER $$
CREATE TRIGGER CancellaTuttoResponsabile BEFORE DELETE ON RESPONSABILE_AZIENDALE
FOR EACH ROW
BEGIN
	-- 1. Scolleghiamo l'azienda (l'azienda resta attiva nel DB)
    UPDATE AZIENDA SET UsernameResponsabile = NULL 
    WHERE UsernameResponsabile = OLD.Username;
    
    -- Eliminiamo le email associate
    DELETE FROM EMAIL WHERE Username = OLD.Username;
END $$
DELIMITER ;

DELIMITER $$
CREATE TRIGGER CancellaTuttoRevisore BEFORE DELETE ON REVISORE_ESG
FOR EACH ROW
BEGIN
	-- 1. Scolleghiamo le Note (restano nel bilancio come riferimento storico)
    UPDATE NOTA SET RevisoreEmittente = NULL 
    WHERE RevisoreEmittente = OLD.Username;
    
    -- 1. Eliminiamo le Valutazioni (non possono stare a NULL perché sono PK)
    DELETE FROM VALUTA_BILANCIO WHERE UsernameRevisore = OLD.Username;
    
	-- 1. Eliminiamo le competenze 
    DELETE FROM COMPETENZA WHERE Username = OLD.Username;
    -- 2. Poi le email associate
    DELETE FROM EMAIL WHERE Username = OLD.Username;
END $$
DELIMITER ;

DELIMITER $$
CREATE TRIGGER CancellaTuttoAzienda BEFORE DELETE ON AZIENDA
FOR EACH ROW
BEGIN
    DELETE FROM BILANCIO_ESERCIZIO WHERE RagioneSocialeAzienda = OLD.RagioneSociale;
END $$
DELIMITER ;

-- qui devo stare attenta all'ordine in cui cancello, perchè potrei bloccare tutto
-- a causa delle foreign key.
DELIMITER $$
CREATE TRIGGER CancellaTuttoBilancio BEFORE DELETE ON BILANCIO_ESERCIZIO
FOR EACH ROW
BEGIN
    DELETE FROM ASSOCIA WHERE IDBilancio = OLD.IDBilancio;
    DELETE FROM NOTA WHERE IDBilancio = OLD.IDBilancio;
    DELETE FROM VALUTA_BILANCIO WHERE IDBilancio = OLD.IDBilancio;
    DELETE FROM VOCE_BILANCIO WHERE IDBilancio = OLD.IDBilancio;
END $$
DELIMITER ;