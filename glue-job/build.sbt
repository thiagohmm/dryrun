name := "financial-transaction-processor"

version := "1.0"

scalaVersion := "2.12.19"

// Repositórios Maven
resolvers ++= Seq(
  "AWS Glue" at "https://aws-glue-etl-artifacts.s3.amazonaws.com/release/"
)

// Configurações do SBT para Java 21
ThisBuild / useCoursier := true
ThisBuild / semanticdbEnabled := false
ThisBuild / javacOptions ++= Seq("-source", "11", "-target", "11")

// Dependências Spark e AWS
libraryDependencies ++= Seq(
  // Spark Core (fornecido pelo runtime do Glue)
  "org.apache.spark" %% "spark-core" % "3.3.0" % "provided",
  "org.apache.spark" %% "spark-sql" % "3.3.0" % "provided",

  // AWS Glue (fornecido pelo runtime)
  "com.amazonaws" % "AWSGlueETL" % "4.0.0" % "provided",

  // AWS SDK para DynamoDB
  "com.amazonaws" % "aws-java-sdk-dynamodb" % "1.12.529",

  // OpenSearch REST Client (somente low-level, compatível com Java 8)
  "org.opensearch.client" % "opensearch-rest-client" % "1.3.13",
  
  // Apache HTTP Client (necessário para OpenSearch)
  "org.apache.httpcomponents" % "httpclient" % "4.5.13",
  "org.apache.httpcomponents" % "httpcore" % "4.4.15",
  "org.apache.httpcomponents" % "httpasyncclient" % "4.1.5",

  // Processamento JSON
  "com.fasterxml.jackson.core" % "jackson-databind" % "2.15.2",
  "com.fasterxml.jackson.module" %% "jackson-module-scala" % "2.15.2",

  // Logging
  "org.slf4j" % "slf4j-api" % "1.7.36" % "provided",

  // Testes (opcional)
  "org.scalatest" %% "scalatest" % "3.2.15" % "test"
)

// Configurações do Assembly para criar JAR fat
assembly / assemblyMergeStrategy := {
  case PathList("META-INF", xs @ _*) => 
    xs match {
      case "MANIFEST.MF" :: Nil => MergeStrategy.discard
      case "services" :: _ => MergeStrategy.concat
      case _ => MergeStrategy.discard
    }
  case "reference.conf" => MergeStrategy.concat
  case _ => MergeStrategy.first
}

// Exclude Spark, Hadoop and logging from assembly (provided by Glue)
assembly / assemblyExcludedJars := {
  val cp = (assembly / fullClasspath).value
  cp.filter { jar =>
    jar.data.getName.startsWith("spark-") ||
    jar.data.getName.startsWith("hadoop-") ||
    jar.data.getName.startsWith("scala-library") ||
    jar.data.getName.startsWith("log4j-") ||
    jar.data.getName.startsWith("slf4j-")
  }
}

// Nome do JAR do Assembly
assembly / assemblyJarName := s"${name.value}_${scalaBinaryVersion.value}-${version.value}.jar"

// Opções do compilador
scalacOptions ++= Seq(
  "-encoding", "UTF-8",
  "-deprecation",
  "-feature",
  "-unchecked",
  "-Xlint"
)
