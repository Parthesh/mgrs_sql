CREATE or replace FUNCTION mgrstolatlon (mgrs text, out lon float, out lat float) as $func$
declare
count_var int; len int; sb text; ii int; zoneNumber int; zoneLetter text;hunK text;
SET_ORIGIN_COLUMN_LETTERS text; SET_ORIGIN_ROW_LETTERS text; A int; I int ;O int; V int;Z int; letters json; NUM_100K_SETS int; setParm int; curCol int; eastingValue float; east100k float; rewindMarker boolean; e text; n text; curRow int; northingValue float; north100k float; remainder int; sep float; sepEasting float; sepEastingString float; sepNorthing float;sepNorthingString float; UTMEasting float; UTMNorthing float; accuracyBonus float; k0 float; aa float; eccSquared float; e1 float; x float; y float; LongOrigin float; eccPrimeSquared float; M float; mu float; phi1Rad float; N1 float ; T1 float; C1 float; R1 float;D float;
begin
	--decode 
	len := length(mgrs);
	sb := substring(mgrs,1,2);
	zoneNumber := sb::int;
	ii := length(sb); 
	ii := ii+1;
	zoneLetter := substring(mgrs,ii,1);
	ii := ii + 1;
	hunK := substring(mgrs,ii,2);
	ii := ii + 2;
	SET_ORIGIN_COLUMN_LETTERS := 'AJSAJS';
	SET_ORIGIN_ROW_LETTERS := 'AFAFAF';
	A := 65;
	I = 73;
	O := 79;
	V := 86;
	Z := 90;
	letters :=json_object( '{C, 1100000.0, D, 2000000.0,E, 2800000.0, F, 3700000.0, G, 4600000.0, H, 5500000.0,J, 6400000.0,K, 7300000.0, L, 8200000.0,M, 9100000.0,N, 0.0,P,800000.0,Q ,1700000.0, R, 2600000.0,S, 3500000.0,T, 4400000.0,U, 5300000.0,V, 6200000.0 ,W, 7000000.0, X, 7900000.0}');
	--get100kSetForZone
	NUM_100K_SETS := 6;
	setParm:= mod(zoneNumber, NUM_100K_SETS);
	if setParm= 0 then 
		setParm:=NUM_100K_SETS;
	end if;
	-- getEastingFromChar
	curCol := ASCII(substring(SET_ORIGIN_COLUMN_LETTERS,setParm,1));
	eastingValue := 100000.0;
	rewindMarker := false;
	e := substring(hunK,1,1);
	count_var := 0;
	while curCol != ascii(e) loop
		count_var := count_var+1;
		if count_var>1000 then
			raise exception 'count>1000 in curcol, probably invalid mgrs: %',mgrs;
		end if;
		curCol := curCol + 1;
		if curCol = I then
			curCol := curCol + 1;
		end if;
		if curCol = O then
			curCol := curCol + 1;
		end if;
		if curCol > Z then
			if rewindMarker = true then
				raise notice 'Bad character: %',e;
			end if;
			curCol := A;
			rewindMarker := true;
		end if;
		eastingValue := eastingValue + 100000.0;
	end loop;
 	count_var:=0;
	east100k:=eastingValue;

	-- getNorthingFromChar
	n := substring(hunK,2,1);
	if n>'V' then
		raise notice 'MGRS Point given invalid Northing %',n;
	end if;
	
	curRow := ASCII(substring(SET_ORIGIN_ROW_LETTERS, setParm,1));
	northingValue := 0.0;
	rewindMarker := false;

	while curRow != ASCII(n) loop
		count_var:=count_var+1;
		if count_var>1000 then
			raise exception 'count>1000 in currow, probably invalid mgrs: %',mgrs;
		end if;
		curRow := curRow + 1;
		if curRow = I then
			curRow := curRow + 1;
		end if;
		if curRow = O then
			curRow := curRow + 1;
		end if;
		if curRow > V then
			if rewindMarker = true then
				raise notice 'Bad character: %',n;
			end if;
			curRow := A;
			rewindMarker := true;
		end if;
		
		northingValue := northingValue + 100000.0;
	end loop;
	count_var := 0;
	north100k := northingValue;
	
	while north100k < json_extract_path_text(letters,zoneLetter)::float loop
		count_var := count_var + 1;
		if count_var>1000 then
			raise exception 'count>1000 in north100k, probably invalid mgrs: %',mgrs;
		end if;
		north100k := north100k + 2000000;
	end loop;
	count_var := 0;
	-- calculate the char index for easting/northing separator
	remainder := len-ii+1; --adjust i for postgres
	
	if mod(remainder,2) != 0 then
		raise notice 'MGRS Point has to have an even number of digits after the zone letter and two 100km letters - front half for easting meters, second half for northing meters %',mgrs;
	end if;
	
	sep := remainder::float/2;
	sepEasting := 0.0;
	sepNorthing := 0.0;
	-- accuracyBonus, sepEastingString, sepNorthingString, easting, northing
	if sep > 0 then
		accuracyBonus := 100000.0 / (10^sep);
		sepEastingString := substring(mgrs,ii,sep::int)::float;
		sepEasting := sepEastingString * accuracyBonus;
		sepNorthingString := substring(mgrs,ii+sep::int,length(mgrs))::float;
		sepNorthing := sepNorthingString * accuracyBonus;
	end if;

	UTMEasting := sepEasting + east100k;
	UTMNorthing := sepNorthing + north100k;

	-- check the zoneNumber is invalid
	if zoneNumber < 0 or zoneNumber > 60 then
		raise notice 'Incorrect zoneNumber: %',zoneNumber;
	end if;

	k0 := 0.9996;
	aa := 6378137.0; -- ellipsoid radius
	eccSquared := 0.00669438; -- ellip.eccsq
	-- eccPrimeSquared
	e1 := (1-sqrt(1-eccSquared)) / (1 + sqrt(1-eccSquared));
	-- remove 500,000 meter offset for longitude
	x := UTMEasting - 500000.0; y:=UTMNorthing;

	if zoneLetter < 'N' then
		y:=y-10000000.0; --remove 10,000,000 meter offset used for southern hemisphere
	end if;

	--There are 60 zones with zone 1 being at West -180 to -174
	LongOrigin := (zoneNumber - 1) * 6 - 180 +3; -- +3 puts origin in middle of zone
	eccPrimeSquared := (eccSquared) /(1-eccSquared);
	M := y/k0;
	mu := M / (aa * (1 - eccSquared / 4 - 3 * eccSquared * eccSquared / 64 - 5 * eccSquared * eccSquared * eccSquared / 256));
	phi1Rad := mu + (3 * e1 / 2 - 27 * e1 * e1 * e1 / 32) * sin(2 * mu) + (21*e1*e1/16-55*e1*e1*e1*e1/32) * sin(4*mu) + (151*e1*e1*e1/96) * sin(6*mu);
	N1 := aa/sqrt(1-eccSquared * sin(phi1Rad) * sin(phi1Rad));
	T1 := tan(phi1Rad) * tan(phi1Rad);
	C1 := eccPrimeSquared * cos(phi1Rad) * cos(phi1Rad);
	R1 := aa * (1-eccSquared) / ((1-eccSquared * sin(phi1Rad) * sin(phi1Rad))^1.5);
	D := x / (N1 * k0);
	lat := phi1Rad - (N1*tan(phi1Rad)/R1) * (D*D/2 - (5+3*T1+10*C1-4*C1*C1-9*eccPrimeSquared) * D*D*D*D / 24 + (61 + 90 *T1 + 298 * C1 + 45 * T1 * T1 - 252 *eccPrimeSquared - 3*C1*C1)*D*D*D*D*D*D/720);
	lat := (180.0*(lat/pi()));
	lon := (D-(1+2*T1+C1)*D*D*D/6+(5-2*C1+28*T1-3*C1*C1+8*eccPrimeSquared+24*T1*T1)*D*D*D*D*D/120)/cos(phi1Rad);
	lon := LongOrigin + (180.0*(lon/pi()));
end
$func$ LANGUAGE plpgsql;

-- select lat,lon from mgrstolatlon('16TEL91579963') 
