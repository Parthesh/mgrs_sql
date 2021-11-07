CREATE or REPLACE function latlontomgrs(lat float, lon float, bin_size int, out mgrs text) as 
$$
declare
A int; I int; O int; V int; Z int; ellip_rad float; eccSquared float; k0 float; latRad float; lonRad float; ZoneNumber int; lonOrigin int; lonOriginRad float; eccPrimeSquared float; N float; T float; C float; AA float; M float; UTMEasting float; UTMNorthing float; zoneLetter text; accuracy int; NUM_100K_SETS int; setParm int; setColumn int; setRow int; SET_ORIGIN_COLUMN_LETTERS text; SET_ORIGIN_ROW_LETTERS text; seasting text; snorthing text; colOrigin int; rowOrigin int; colInt int; rowInt int; rollover boolean; twoLetter text;
begin
    if bin_size=100000 then accuracy:=0;
    elsif bin_size=10000 then accuracy:=1;
    elsif bin_size=1000 then accuracy:=2;
    elsif bin_size=100 then accuracy:=3;
    elsif bin_size=10 then accuracy:=4;
    else raise exception 'Invalid mgrs precision detected:% , it can be value in (10,100,1000,10000,100000)',bin_size::text;
    end if;
    -- LLtoUTM
    A:=65; I := 73; O :=79; V := 86; Z := 90;
    NUM_100K_SETS := 6;
    SET_ORIGIN_COLUMN_LETTERS := 'AJSAJS';
    SET_ORIGIN_ROW_LETTERS := 'AFAFAF';
    ellip_rad := 6378137.0; -- ellip.radius
    eccSquared := 0.00669438; --ellip.eccsq
    k0 := 0.9996;
    latRad := radians(lat);
    lonRad := radians(lon);
    ZoneNumber := floor((lon+180)/6)+1;

    -- Make sure the longitude 180.0 is in zone 60
    if lon = 180 then   
        ZoneNumber := 60;
    end if;

    -- Special zone for Norway
    if lat >= 56.0 and lat < 64.0 and lon >= 3.0 and lon < 12.0 then 
        ZoneNumber := 32;
    end if;

    -- special zones for Svalbard
    if lat >= 72.0 and lat < 84.0 then
        if lon >= 0.0 and lon < 9.0 then
            ZoneNumber := 31;
        elsif lon>=9.0 and lon<21.0 then
            ZoneNumber:=33;
        elsif lon>=21.0 and lon <33.0 then
            ZoneNumber := 35;
        elsif lon>33.0 and lon<42.0 then
            ZoneNumber:=37;
        end if;
    end if;

    lonOrigin:=(ZoneNumber-1)*6-180+3; -- +3 puts origin in middle of zone
    lonOriginRad:=radians(lonOrigin);
    eccPrimeSquared:=(eccSquared)/(1-eccSquared);

    N:=ellip_rad/sqrt(1-eccSquared*sin(latRad)*sin(latRad));
    T:=tan(latRad)*tan(latRad);
    C:=eccPrimeSquared*cos(latRad)*cos(latRad);
    AA:=cos(latRad)*(lonRad-lonOriginRad);

    M:=ellip_rad*((1-eccSquared/4-3*eccSquared*eccSquared/64-5*eccSquared*eccSquared*eccSquared/256)*latRad-(3*eccSquared/8+3*eccSquared*eccSquared/32+45*eccSquared*eccSquared*eccSquared/1024)*sin(2*latRad)+(15*eccSquared*eccSquared/256+45*eccSquared*eccSquared*eccSquared/1024)*sin(4*latRad)-(35*eccSquared*eccSquared*eccSquared/3072)*sin(6*latRad));
	
    UTMEasting:=round((k0*N*(AA+(1-T+C)*AA*AA*AA/6.0+(5-18*T+T*T+72*C-58*eccPrimeSquared)*AA*AA*AA*AA*AA/120.0)+500000.0));
   
    UTMNorthing:=round((k0 *(M+N*tan(latRad)*(AA*AA/2+(5-T+9*C+4*C*C)*AA*AA*AA*AA/24.0+(61-58*T+T*T+600*C-330*eccPrimeSquared)*AA*AA*AA*AA*AA*AA/720.0))));

    if lat<0.0 then
        UTMNorthing:=UTMNorthing + 10000000.0; -- offset for southern hemisphere
    end if;

    -- getzoneLetter
    zoneLetter:='Z';
    if (84>=lat) and (lat>=72) then zoneLetter:='X';
    elsif (72>lat) and (lat>=64) then zoneLetter:='W';
    elsif (64>lat) and (lat>=56) then zoneLetter:='V';
    elsif (56>lat) and (lat>=48) then zoneLetter:='U';
    elsif (48>lat) and (lat>=40) then zoneLetter:='T';
    elsif (40>lat) and (lat>=32) then zoneLetter:='S';
    elsif (32>lat) and (lat>=24) then zoneLetter:='R';
    elsif (24>lat) and (lat>=16) then zoneLetter:='Q';
    elsif (16>lat) and (lat>=8) then zoneLetter:='P';
    elsif (8>lat) and (lat>=0) then zoneLetter:='N';
    elsif (0>lat) and (lat>=-8) then zoneLetter:='M';
    elsif (-8>lat) and (lat>=-16) then zoneLetter:='L';
    elsif (-16>lat) and (lat>=-24) then zoneLetter:='K';
    elsif (-24>lat) and (lat>=-32) then zoneLetter:='J';
    elsif (-32>lat) and (lat>=-40) then zoneLetter:='H';
    elsif (-40>lat) and (lat>=-48) then zoneLetter:='G';
    elsif (-48>lat) and (lat>=-56) then zoneLetter:='F';
    elsif (-56>lat) and (lat>=-64) then zoneLetter:='E';
    elsif (-64>lat) and (lat>=-72) then zoneLetter:='D';
    elsif (-72>lat) and (lat>=-80) then zoneLetter:='C';
    end if;

    --encode
    seasting:='00000' || UTMEasting::text;
    snorthing:='00000' || UTMNorthing::text;
    -- get100kID
    setParm:=mod(ZoneNumber,NUM_100K_SETS);
    if setParm=0 then setParm:=NUM_100K_SETS; end if;
    setColumn:=floor(UTMEasting/100000);
    setRow:=mod(floor(UTMNorthing/100000)::int,20);
    -- getLetter100kID
    colOrigin:=ascii(substring(SET_ORIGIN_COLUMN_LETTERS,setParm,1));
    rowOrigin:=ascii(substring(SET_ORIGIN_ROW_LETTERS,setParm,1));
    -- colInt and rowInt are the letters to build to return
    colInt := colOrigin + setColumn - 1;
    rowInt := rowOrigin + setRow;
    rollover:=false;
    if colInt>Z then colInt:=colInt-Z+A-1; rollover:=true; end if;
    if (colInt=I or (colOrigin<I and colInt>I) or ((colInt>I or colOrigin<I) and rollover=True)) then colInt:=colInt+1; end if;
    if colInt=I then colInt:=colInt+1; end if;
    if colInt>Z then colInt:=colInt-Z+A-1; end if;
    if rowInt>V then rowInt:=rowInt-V+A-1; rollover:=true; else rollover:=false; end if;
    if (((rowInt=I) or ((rowOrigin<I) and (rowInt>I))) or (((rowInt>I) or (rowOrigin<I)) and rollover=True)) then rowInt:=rowInt+1; end if;
    if (((rowInt=0) or ((rowOrigin<O) and (rowInt>O))) or (((rowInt>O) or (rowOrigin<O)) and rollover=True)) then rowInt:=rowInt+1; end if;
    if rowInt=I then rowInt:=rowInt+1; end if;
    if rowInt>V then rowInt:=rowInt-V+A-1; end if;
    twoLetter:=chr(colInt) || chr(rowInt);

    mgrs := LPAD(ZoneNumber::text,2,'0') || zoneLetter || twoLetter || left(right(seasting,5),accuracy) || left(right(snorthing,5),accuracy);

end$$ LANGUAGE plpgsql;

--select latlontomgrs(42.283250472918425,-83.20515721750853,10);
