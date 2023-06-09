CREATE OR ALTER FUNCTION [dbo].[fn_CsvToTable] ( @StringInput NVARCHAR(max))
RETURNS @OutputTable TABLE ([ItemNumber] int, [ItemValue] NVARCHAR(max) )
AS
BEGIN

	DECLARE @Delimiter varchar(1) = ','
	DECLARE @Quote varchar(1) = '"'
	DECLARE @InQuote bit = 'false'
	DECLARE @Next varchar(1)
	DECLARE @StartLocation int

    DECLARE @String NVARCHAR(max)
	DECLARE @RowNumber int = 0

    WHILE LEN(@StringInput) > 0
    BEGIN
		IF LEFT(@StringInput, 1) = @Quote
		BEGIN
		    SET @InQuote = 'true'
			SET @String = ''

			WHILE @InQuote = 'true'
			BEGIN
				-- remove the starting quote
				SET @StringInput = SUBSTRING(@StringInput, 2, LEN(@StringInput))

				-- gather the characters up to the next quote
				SET @String = @String + LEFT(@StringInput, 
										ISNULL(NULLIF(CHARINDEX(@Quote, @StringInput) - 1, -1),
										LEN(@StringInput)))

                -- remove the characters we just gathered, plus the next quote
				SET @StringInput = SUBSTRING(@StringInput,
											 ISNULL(NULLIF(CHARINDEX(@Quote, @StringInput), 0),
											 LEN(@StringInput)) + 1, LEN(@StringInput)) 

				IF LEFT(@StringInput, 1) = @Quote 
                -- this means the quote we just removed was escaping this quote
				BEGIN
					SET @String = @String + '"'
				END

				ELSE 
                --this means the quote we removed was the end if the string
				BEGIN
					SET @InQuote = 'false'
				END
			END
		END
		ELSE
		BEGIN
			SET @String = LEFT(@StringInput, 
									ISNULL(NULLIF(CHARINDEX(@Delimiter, @StringInput) - 1, -1),
									LEN(@StringInput)))

			SET @StringInput = SUBSTRING(@StringInput, LEN(@String) + 1,  LEN(@StringInput))
		END

		set @RowNumber = @RowNumber + 1
        INSERT INTO @OutputTable ( ItemNumber, [ItemValue] )
        VALUES (@RowNumber, REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@String)), CHAR(10), ''), CHAR(13), ''), CHAR(9), '') )        

		--special case for string ends with comma
		IF @StringInput = @Delimiter
		BEGIN
			set @RowNumber = @RowNumber + 1
			INSERT INTO @OutputTable ( ItemNumber, [ItemValue] )
			VALUES (@RowNumber, '' )
		END

        --now advance past the comma
		SET @StringInput = SUBSTRING(@StringInput, 2,  LEN(@StringInput))
    END

    RETURN
END
